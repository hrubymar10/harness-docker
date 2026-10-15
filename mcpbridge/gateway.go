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

// upstreamRestartTimeout bounds restarting an exited upstream, so a command
// that starts but never completes the MCP handshake cannot hold the upstream
// lock, and with it later requests and shutdown, indefinitely.
var upstreamRestartTimeout = 30 * time.Second

type upstream struct {
	name     string
	cfg      serverConfig
	client   *mcp.Client
	sessionM sync.Mutex
	session  *mcp.ClientSession
	exited   bool
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
		u := &upstream{name: serverCfg.Name, cfg: serverCfg, tools: make(map[string]string), prompts: make(map[string]string)}
		u.client = mcp.NewClient(&mcp.Implementation{Name: "mcpbridge-" + serverCfg.Name, Version: "1"}, &mcp.ClientOptions{
			ToolListChangedHandler: func(context.Context, *mcp.ToolListChangedRequest) {
				go g.refreshUpstream(u)
			},
			PromptListChangedHandler: func(context.Context, *mcp.PromptListChangedRequest) {
				go g.refreshUpstream(u)
			},
		})
		u.sessionM.Lock()
		err := g.connect(ctx, u)
		session := u.session
		u.sessionM.Unlock()
		if err != nil {
			g.Close()
			return nil, fmt.Errorf("start upstream %q: %w", serverCfg.Name, err)
		}
		g.upstreams = append(g.upstreams, u)
		if err := g.refresh(ctx, u, session); err != nil {
			g.Close()
			return nil, fmt.Errorf("load upstream %q: %w", serverCfg.Name, err)
		}
	}
	if len(g.upstreams) == 0 {
		return nil, fmt.Errorf("no enabled servers")
	}
	return g, nil
}

// connect starts the upstream command and records the new session. The caller
// must hold u.sessionM.
func (g *gateway) connect(ctx context.Context, u *upstream) error {
	cmd := exec.Command(u.cfg.Command, u.cfg.Args...)
	cmd.Dir = u.cfg.CWD
	cmd.Env = mergedEnv(u.cfg.Env)
	cmd.Stderr = os.Stderr
	session, err := u.client.Connect(ctx, &mcp.CommandTransport{Command: cmd}, nil)
	if err != nil {
		return err
	}
	u.session = session
	u.exited = false
	go g.watch(u, session)
	return nil
}

// watch marks the upstream as exited when its process closes the connection,
// for example when the host application behind it quits. The next request
// restarts it instead of writing to the closed pipe.
func (g *gateway) watch(u *upstream, session *mcp.ClientSession) {
	err := session.Wait()
	u.sessionM.Lock()
	current := u.session == session
	if current {
		u.exited = true
	}
	u.sessionM.Unlock()
	g.mu.Lock()
	closed := g.closed
	g.mu.Unlock()
	if current && !closed {
		log.Printf("WARN: upstream %q exited (%v); restarting it on the next request", u.name, err)
	}
}

// liveSession returns the upstream session, restarting the upstream first if
// its process has exited. A call that fails because the upstream dies while
// it is in flight is not retried, because the upstream may already have acted
// on it.
func (g *gateway) liveSession(ctx context.Context, u *upstream) (*mcp.ClientSession, error) {
	u.sessionM.Lock()
	if !u.exited {
		session := u.session
		u.sessionM.Unlock()
		return session, nil
	}
	g.mu.Lock()
	closed := g.closed
	g.mu.Unlock()
	if closed {
		u.sessionM.Unlock()
		return nil, fmt.Errorf("gateway is closed")
	}
	_ = u.session.Close()
	restartCtx, cancel := context.WithTimeout(ctx, upstreamRestartTimeout)
	defer cancel()
	if err := g.connect(restartCtx, u); err != nil {
		u.sessionM.Unlock()
		return nil, fmt.Errorf("restart upstream %q: %w", u.name, err)
	}
	session := u.session
	u.sessionM.Unlock()
	log.Printf("upstream %q restarted", u.name)
	if err := g.refresh(ctx, u, session); err != nil {
		log.Printf("WARN: refresh restarted upstream %q: %v", u.name, err)
	}
	return session, nil
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
	u.sessionM.Lock()
	session := u.session
	u.sessionM.Unlock()
	if err := g.refresh(ctx, u, session); err != nil {
		log.Printf("WARN: refresh upstream %q: %v", u.name, err)
	}
}

func (g *gateway) refresh(ctx context.Context, u *upstream, session *mcp.ClientSession) error {
	u.refreshM.Lock()
	defer u.refreshM.Unlock()
	tools, err := listAllTools(ctx, session)
	if err != nil {
		return fmt.Errorf("list tools: %w", err)
	}
	prompts, err := listAllPrompts(ctx, session)
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
			session, err := g.liveSession(ctx, u)
			if err != nil {
				return nil, err
			}
			return session.CallTool(ctx, &mcp.CallToolParams{
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
			session, err := g.liveSession(ctx, u)
			if err != nil {
				return nil, err
			}
			return session.GetPrompt(ctx, &mcp.GetPromptParams{
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
		u.sessionM.Lock()
		session := u.session
		u.sessionM.Unlock()
		if session != nil {
			_ = session.Close()
		}
	}
}
