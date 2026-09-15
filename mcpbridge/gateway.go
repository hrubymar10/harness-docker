package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/exec"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

type upstream struct {
	name     string
	session  *mcp.ClientSession
	tools    map[string]string
	prompts  map[string]string
	refreshM sync.Mutex
}

type gateway struct {
	server    *mcp.Server
	upstreams []*upstream
	mu        sync.Mutex
	closed    bool
}

func newGateway(ctx context.Context, cfg *config) (*gateway, error) {
	g := &gateway{server: mcp.NewServer(&mcp.Implementation{Name: "mcpbridge", Version: "1"}, &mcp.ServerOptions{
		Capabilities: &mcp.ServerCapabilities{
			Tools:   &mcp.ToolCapabilities{ListChanged: true},
			Prompts: &mcp.PromptCapabilities{ListChanged: true},
		},
	})}
	for _, serverCfg := range cfg.Servers {
		if !serverCfg.isEnabled() {
			continue
		}
		u := &upstream{name: serverCfg.Name, tools: make(map[string]string), prompts: make(map[string]string)}
		client := mcp.NewClient(&mcp.Implementation{Name: "mcpbridge-" + serverCfg.Name, Version: "1"}, &mcp.ClientOptions{
			ToolListChangedHandler: func(context.Context, *mcp.ToolListChangedRequest) {
				go g.refreshUpstream(u)
			},
			PromptListChangedHandler: func(context.Context, *mcp.PromptListChangedRequest) {
				go g.refreshUpstream(u)
			},
		})
		cmd := exec.Command(serverCfg.Command, serverCfg.Args...)
		cmd.Dir = serverCfg.CWD
		cmd.Env = mergedEnv(serverCfg.Env)
		cmd.Stderr = os.Stderr
		session, err := client.Connect(ctx, &mcp.CommandTransport{Command: cmd}, nil)
		if err != nil {
			g.Close()
			return nil, fmt.Errorf("start upstream %q: %w", serverCfg.Name, err)
		}
		u.session = session
		g.upstreams = append(g.upstreams, u)
		if err := g.refresh(ctx, u); err != nil {
			g.Close()
			return nil, fmt.Errorf("load upstream %q: %w", serverCfg.Name, err)
		}
	}
	if len(g.upstreams) == 0 {
		return nil, fmt.Errorf("no enabled servers")
	}
	return g, nil
}

func mergedEnv(overrides map[string]string) []string {
	env := make([]string, 0, len(os.Environ())+len(overrides))
	for _, entry := range os.Environ() {
		key, _, _ := strings.Cut(entry, "=")
		if _, overridden := overrides[key]; !overridden {
			env = append(env, entry)
		}
	}
	keys := make([]string, 0, len(overrides))
	for key := range overrides {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys {
		env = append(env, key+"="+overrides[key])
	}
	return env
}

func (g *gateway) refreshUpstream(u *upstream) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	if err := g.refresh(ctx, u); err != nil {
		log.Printf("WARN: refresh upstream %q: %v", u.name, err)
	}
}

func (g *gateway) refresh(ctx context.Context, u *upstream) error {
	u.refreshM.Lock()
	defer u.refreshM.Unlock()
	tools, err := listAllTools(ctx, u.session)
	if err != nil {
		return fmt.Errorf("list tools: %w", err)
	}
	prompts, err := listAllPrompts(ctx, u.session)
	if err != nil {
		return fmt.Errorf("list prompts: %w", err)
	}

	newTools := make(map[string]string, len(tools))
	for _, tool := range tools {
		if tool == nil {
			return fmt.Errorf("tool list contains a null entry")
		}
		publicName := u.name + "." + tool.Name
		if len(publicName) > 128 || !validUpstreamName(tool.Name) {
			return fmt.Errorf("tool name %q cannot be namespaced as %q", tool.Name, publicName)
		}
		if err := validateToolSchema(tool.Name, "input", tool.InputSchema, true); err != nil {
			return err
		}
		if err := validateToolSchema(tool.Name, "output", tool.OutputSchema, false); err != nil {
			return err
		}
		if _, duplicate := newTools[publicName]; duplicate {
			return fmt.Errorf("tool %q is duplicated", tool.Name)
		}
		newTools[publicName] = tool.Name
	}
	newPrompts := make(map[string]string, len(prompts))
	for _, prompt := range prompts {
		if prompt == nil {
			return fmt.Errorf("prompt list contains a null entry")
		}
		publicName := u.name + "." + prompt.Name
		if len(publicName) > 128 || !validUpstreamName(prompt.Name) {
			return fmt.Errorf("prompt name %q cannot be namespaced as %q", prompt.Name, publicName)
		}
		if _, duplicate := newPrompts[publicName]; duplicate {
			return fmt.Errorf("prompt %q is duplicated", prompt.Name)
		}
		newPrompts[publicName] = prompt.Name
	}

	g.mu.Lock()
	defer g.mu.Unlock()
	if g.closed {
		return nil
	}
	for _, tool := range tools {
		publicName := u.name + "." + tool.Name
		clone := *tool
		clone.Name = publicName
		g.server.AddTool(&clone, func(ctx context.Context, req *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			g.mu.Lock()
			originalName, ok := u.tools[publicName]
			g.mu.Unlock()
			if !ok {
				return nil, fmt.Errorf("tool %q is no longer available", publicName)
			}
			return u.session.CallTool(ctx, &mcp.CallToolParams{
				Meta:      req.Params.Meta,
				Name:      originalName,
				Arguments: req.Params.Arguments,
			})
		})
	}
	for oldName := range u.tools {
		if _, ok := newTools[oldName]; !ok {
			g.server.RemoveTools(oldName)
		}
	}
	u.tools = newTools

	for _, prompt := range prompts {
		publicName := u.name + "." + prompt.Name
		clone := *prompt
		clone.Name = publicName
		g.server.AddPrompt(&clone, func(ctx context.Context, req *mcp.GetPromptRequest) (*mcp.GetPromptResult, error) {
			g.mu.Lock()
			originalName, ok := u.prompts[publicName]
			g.mu.Unlock()
			if !ok {
				return nil, fmt.Errorf("prompt %q is no longer available", publicName)
			}
			return u.session.GetPrompt(ctx, &mcp.GetPromptParams{
				Meta:      req.Params.Meta,
				Name:      originalName,
				Arguments: req.Params.Arguments,
			})
		})
	}
	for oldName := range u.prompts {
		if _, ok := newPrompts[oldName]; !ok {
			g.server.RemovePrompts(oldName)
		}
	}
	u.prompts = newPrompts
	return nil
}

func validateToolSchema(toolName, kind string, schema any, required bool) error {
	if schema == nil {
		if required {
			return fmt.Errorf("tool %q has no %s schema", toolName, kind)
		}
		return nil
	}
	raw, err := json.Marshal(schema)
	if err != nil {
		return fmt.Errorf("tool %q has an invalid %s schema: %w", toolName, kind, err)
	}
	var object map[string]any
	if err := json.Unmarshal(raw, &object); err != nil {
		return fmt.Errorf("tool %q has an invalid %s schema: %w", toolName, kind, err)
	}
	if object["type"] != "object" {
		return fmt.Errorf("tool %q %s schema must have type object", toolName, kind)
	}
	return nil
}

func validUpstreamName(name string) bool {
	if name == "" {
		return false
	}
	for _, r := range name {
		if !((r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '_' || r == '-' || r == '.') {
			return false
		}
	}
	return true
}

func listAllTools(ctx context.Context, session *mcp.ClientSession) ([]*mcp.Tool, error) {
	if result := session.InitializeResult(); result == nil || result.Capabilities == nil || result.Capabilities.Tools == nil {
		return nil, nil
	}
	var tools []*mcp.Tool
	params := &mcp.ListToolsParams{}
	for {
		result, err := session.ListTools(ctx, params)
		if err != nil {
			return nil, err
		}
		tools = append(tools, result.Tools...)
		if result.NextCursor == "" {
			return tools, nil
		}
		params.Cursor = result.NextCursor
	}
}

func listAllPrompts(ctx context.Context, session *mcp.ClientSession) ([]*mcp.Prompt, error) {
	if result := session.InitializeResult(); result == nil || result.Capabilities == nil || result.Capabilities.Prompts == nil {
		return nil, nil
	}
	var prompts []*mcp.Prompt
	params := &mcp.ListPromptsParams{}
	for {
		result, err := session.ListPrompts(ctx, params)
		if err != nil {
			return nil, err
		}
		prompts = append(prompts, result.Prompts...)
		if result.NextCursor == "" {
			return prompts, nil
		}
		params.Cursor = result.NextCursor
	}
}

func (g *gateway) Close() {
	g.mu.Lock()
	if g.closed {
		g.mu.Unlock()
		return
	}
	g.closed = true
	upstreams := append([]*upstream(nil), g.upstreams...)
	g.mu.Unlock()
	for _, u := range upstreams {
		if u.session != nil {
			_ = u.session.Close()
		}
	}
}
