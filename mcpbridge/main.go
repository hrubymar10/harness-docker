package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/netip"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(args []string) int {
	if len(args) != 3 || (args[0] != "serve" && args[0] != "configured") || args[1] != "--config" {
		fmt.Fprintln(os.Stderr, "usage: mcpbridge <serve|configured> --config CONFIG")
		return 2
	}
	cfg, err := readConfig(args[2])
	if err != nil {
		fmt.Fprintf(os.Stderr, "mcpbridge: %v\n", err)
		return 2
	}
	if args[0] == "configured" {
		if enabledServerCount(cfg) == 0 {
			return 1
		}
		return 0
	}
	if enabledServerCount(cfg) == 0 {
		fmt.Fprintln(os.Stderr, "mcpbridge: no enabled servers")
		return 2
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := serve(ctx, cfg); err != nil {
		fmt.Fprintf(os.Stderr, "mcpbridge: %v\n", err)
		return 1
	}
	return 0
}

func serve(ctx context.Context, cfg *config) error {
	gateway, err := newGateway(ctx, cfg)
	if err != nil {
		return err
	}
	defer gateway.Close()
	allow, err := parseAllowList(cfg.AllowList)
	if err != nil {
		return err
	}
	mux := http.NewServeMux()
	mux.Handle("/mcp", mcp.NewStreamableHTTPHandler(func(*http.Request) *mcp.Server {
		return gateway.server
	}, nil))
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	listener, err := net.Listen("tcp", cfg.Listen)
	if err != nil {
		return err
	}
	server := &http.Server{Handler: allowMiddleware(mux, allow), ReadHeaderTimeout: 5 * time.Second}
	host, _, _ := net.SplitHostPort(cfg.Listen)
	if ip, err := netip.ParseAddr(host); err == nil && !ip.IsLoopback() {
		log.Printf("WARN: bound to %s — allow_list gates access but configured MCP servers run with host privileges", host)
	}
	log.Printf("mcpbridge listening on http://%s/mcp (allow: %v)", cfg.Listen, allow)
	errCh := make(chan error, 1)
	go func() { errCh <- server.Serve(listener) }()
	select {
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := server.Shutdown(shutdownCtx); err != nil {
			return err
		}
		return nil
	case err := <-errCh:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return err
	}
}
