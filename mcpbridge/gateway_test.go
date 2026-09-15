package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/netip"
	"os"
	"testing"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

func TestMCPBridgeHelperProcess(t *testing.T) {
	if os.Getenv("MCPBRIDGE_HELPER") != "1" {
		return
	}
	server := mcp.NewServer(&mcp.Implementation{Name: "fake", Version: "1"}, nil)
	server.AddTool(&mcp.Tool{Name: "echo", InputSchema: map[string]any{"type": "object"}}, func(_ context.Context, req *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		var args map[string]any
		if err := json.Unmarshal(req.Params.Arguments, &args); err != nil {
			return nil, err
		}
		return &mcp.CallToolResult{Content: []mcp.Content{&mcp.TextContent{Text: fmt.Sprint(args["text"])}}}, nil
	})
	server.AddTool(&mcp.Tool{Name: "trigger", InputSchema: map[string]any{"type": "object"}}, func(context.Context, *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		server.RemoveTools("echo")
		server.AddTool(&mcp.Tool{Name: "later", InputSchema: map[string]any{"type": "object"}}, func(context.Context, *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			return &mcp.CallToolResult{Content: []mcp.Content{&mcp.TextContent{Text: "later"}}}, nil
		})
		server.RemovePrompts("hello")
		server.AddPrompt(&mcp.Prompt{Name: "later_prompt"}, func(context.Context, *mcp.GetPromptRequest) (*mcp.GetPromptResult, error) {
			return &mcp.GetPromptResult{Messages: []*mcp.PromptMessage{{Role: "user", Content: &mcp.TextContent{Text: "later"}}}}, nil
		})
		return &mcp.CallToolResult{Content: []mcp.Content{&mcp.TextContent{Text: "triggered"}}}, nil
	})
	server.AddPrompt(&mcp.Prompt{Name: "hello"}, func(_ context.Context, req *mcp.GetPromptRequest) (*mcp.GetPromptResult, error) {
		return &mcp.GetPromptResult{Messages: []*mcp.PromptMessage{{Role: "user", Content: &mcp.TextContent{Text: "hello " + req.Params.Arguments["name"]}}}}, nil
	})
	_ = server.Run(context.Background(), &mcp.StdioTransport{})
	os.Exit(0)
}

func helperConfig() *config {
	enabled := true
	return &config{
		Listen:    defaultListen,
		AllowList: []string{"127.0.0.0/8"},
		Servers: []serverConfig{{
			Name:    "fake",
			Command: os.Args[0],
			Args:    []string{"-test.run=TestMCPBridgeHelperProcess"},
			Env:     map[string]string{"MCPBRIDGE_HELPER": "1"},
			Enabled: &enabled,
		}},
	}
}

func connectGatewayClient(t *testing.T, server *mcp.Server) *mcp.ClientSession {
	t.Helper()
	serverTransport, clientTransport := mcp.NewInMemoryTransports()
	if _, err := server.Connect(context.Background(), serverTransport, nil); err != nil {
		t.Fatal(err)
	}
	client := mcp.NewClient(&mcp.Implementation{Name: "test", Version: "1"}, nil)
	session, err := client.Connect(context.Background(), clientTransport, nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = session.Close() })
	return session
}

func TestGatewayNamespacesAndRoutes(t *testing.T) {
	gateway, err := newGateway(context.Background(), helperConfig())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(gateway.Close)
	session := connectGatewayClient(t, gateway.server)

	tools, err := session.ListTools(context.Background(), nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(tools.Tools) != 2 || tools.Tools[0].Name != "fake.echo" || tools.Tools[1].Name != "fake.trigger" {
		t.Fatalf("unexpected tools: %#v", tools.Tools)
	}
	result, err := session.CallTool(context.Background(), &mcp.CallToolParams{Name: "fake.echo", Arguments: map[string]any{"text": "round trip"}})
	if err != nil {
		t.Fatal(err)
	}
	if got := result.Content[0].(*mcp.TextContent).Text; got != "round trip" {
		t.Fatalf("echo result = %q", got)
	}

	prompts, err := session.ListPrompts(context.Background(), nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(prompts.Prompts) != 1 || prompts.Prompts[0].Name != "fake.hello" {
		t.Fatalf("unexpected prompts: %#v", prompts.Prompts)
	}
	prompt, err := session.GetPrompt(context.Background(), &mcp.GetPromptParams{Name: "fake.hello", Arguments: map[string]string{"name": "world"}})
	if err != nil {
		t.Fatal(err)
	}
	if got := prompt.Messages[0].Content.(*mcp.TextContent).Text; got != "hello world" {
		t.Fatalf("prompt result = %q", got)
	}
}

func TestGatewayForwardsListChanges(t *testing.T) {
	gateway, err := newGateway(context.Background(), helperConfig())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(gateway.Close)
	session := connectGatewayClient(t, gateway.server)
	if _, err := session.CallTool(context.Background(), &mcp.CallToolParams{Name: "fake.trigger"}); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		toolResult, err := session.ListTools(context.Background(), nil)
		if err != nil {
			t.Fatal(err)
		}
		foundLater, foundEcho := false, false
		for _, tool := range toolResult.Tools {
			if tool.Name == "fake.later" {
				foundLater = true
			}
			if tool.Name == "fake.echo" {
				foundEcho = true
			}
		}
		promptResult, err := session.ListPrompts(context.Background(), nil)
		if err != nil {
			t.Fatal(err)
		}
		foundLaterPrompt, foundHello := false, false
		for _, prompt := range promptResult.Prompts {
			if prompt.Name == "fake.later_prompt" {
				foundLaterPrompt = true
			}
			if prompt.Name == "fake.hello" {
				foundHello = true
			}
		}
		if foundLater && !foundEcho && foundLaterPrompt && !foundHello {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatal("namespaced tool and prompt changes were not observed")
}

func TestGatewayServesStreamableHTTP(t *testing.T) {
	gateway, err := newGateway(context.Background(), helperConfig())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(gateway.Close)
	mux := http.NewServeMux()
	mux.Handle("/mcp", mcp.NewStreamableHTTPHandler(func(*http.Request) *mcp.Server { return gateway.server }, nil))
	server := httptest.NewServer(allowMiddleware(mux, []netip.Prefix{netip.MustParsePrefix("127.0.0.0/8")}))
	t.Cleanup(server.Close)
	client := mcp.NewClient(&mcp.Implementation{Name: "http-test", Version: "1"}, nil)
	session, err := client.Connect(context.Background(), &mcp.StreamableClientTransport{Endpoint: server.URL + "/mcp"}, nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = session.Close() })
	result, err := session.ListTools(context.Background(), nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Tools) != 2 || result.Tools[0].Name != "fake.echo" {
		t.Fatalf("unexpected HTTP tool list: %#v", result.Tools)
	}
}
