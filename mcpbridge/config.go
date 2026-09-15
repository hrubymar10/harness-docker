package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/netip"
	"os"
	"regexp"
	"strings"
)

const defaultListen = "127.0.0.1:9976"

var serverNameRE = regexp.MustCompile(`^[A-Za-z0-9_-]+$`)

type config struct {
	Listen    string         `json:"listen"`
	AllowList []string       `json:"allow_list"`
	Servers   []serverConfig `json:"servers"`
}

type serverConfig struct {
	Name    string            `json:"name"`
	Command string            `json:"command"`
	Args    []string          `json:"args"`
	Env     map[string]string `json:"env"`
	Enabled *bool             `json:"enabled"`
	CWD     string            `json:"cwd"`
}

func (s serverConfig) isEnabled() bool {
	return s.Enabled == nil || *s.Enabled
}

func readConfig(path string) (*config, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	clean, err := stripJSONComments(raw)
	if err != nil {
		return nil, fmt.Errorf("parse JSONC: %w", err)
	}
	dec := json.NewDecoder(bytes.NewReader(clean))
	dec.DisallowUnknownFields()
	var cfg config
	if err := dec.Decode(&cfg); err != nil {
		return nil, fmt.Errorf("parse JSONC: %w", err)
	}
	var trailing any
	if err := dec.Decode(&trailing); err != io.EOF {
		if err == nil {
			return nil, fmt.Errorf("parse JSONC: unexpected trailing value")
		}
		return nil, fmt.Errorf("parse JSONC: %w", err)
	}
	if cfg.Listen == "" {
		cfg.Listen = defaultListen
	}
	if cfg.AllowList == nil {
		cfg.AllowList = []string{"127.0.0.0/8", "::1/128"}
	}
	if err := validateConfig(&cfg); err != nil {
		return nil, err
	}
	return &cfg, nil
}

func stripJSONComments(src []byte) ([]byte, error) {
	out := append([]byte(nil), src...)
	inString, escaped := false, false
	for i := 0; i < len(src); i++ {
		if inString {
			if escaped {
				escaped = false
				continue
			}
			switch src[i] {
			case '\\':
				escaped = true
			case '"':
				inString = false
			}
			continue
		}
		if src[i] == '"' {
			inString = true
			continue
		}
		if src[i] != '/' || i+1 >= len(src) {
			continue
		}
		switch src[i+1] {
		case '/':
			out[i], out[i+1] = ' ', ' '
			i += 2
			for ; i < len(src) && src[i] != '\n' && src[i] != '\r'; i++ {
				out[i] = ' '
			}
			i--
		case '*':
			out[i], out[i+1] = ' ', ' '
			i += 2
			closed := false
			for ; i < len(src); i++ {
				if src[i] == '*' && i+1 < len(src) && src[i+1] == '/' {
					out[i], out[i+1] = ' ', ' '
					i++
					closed = true
					break
				}
				if src[i] != '\n' && src[i] != '\r' {
					out[i] = ' '
				}
			}
			if !closed {
				return nil, fmt.Errorf("unterminated block comment")
			}
		}
	}
	if inString {
		return nil, fmt.Errorf("unterminated string")
	}
	return out, nil
}

func validateConfig(cfg *config) error {
	host, port, err := net.SplitHostPort(cfg.Listen)
	if err != nil {
		return fmt.Errorf("listen %q: %w", cfg.Listen, err)
	}
	if host == "" {
		return fmt.Errorf("listen %q: empty host; use an IP literal", cfg.Listen)
	}
	if _, err := netip.ParseAddr(host); err != nil {
		return fmt.Errorf("listen %q: host must be an IP literal: %w", cfg.Listen, err)
	}
	if _, err := net.LookupPort("tcp", port); err != nil {
		return fmt.Errorf("listen %q: invalid port: %w", cfg.Listen, err)
	}
	if len(cfg.AllowList) == 0 {
		return fmt.Errorf("allow_list must contain at least one IP or CIDR")
	}
	if _, err := parseAllowList(cfg.AllowList); err != nil {
		return err
	}
	seen := make(map[string]bool)
	for i, server := range cfg.Servers {
		if server.Name == "" || !serverNameRE.MatchString(server.Name) {
			return fmt.Errorf("servers[%d].name %q: use only letters, digits, underscores, and hyphens", i, server.Name)
		}
		if seen[server.Name] {
			return fmt.Errorf("servers[%d].name %q is duplicated", i, server.Name)
		}
		seen[server.Name] = true
		if server.Command == "" {
			return fmt.Errorf("servers[%d].command must not be empty", i)
		}
		for key := range server.Env {
			if key == "" || strings.ContainsAny(key, "=\x00") {
				return fmt.Errorf("servers[%d].env contains invalid variable name %q", i, key)
			}
		}
	}
	return nil
}

func enabledServerCount(cfg *config) int {
	count := 0
	for _, server := range cfg.Servers {
		if server.isEnabled() {
			count++
		}
	}
	return count
}
