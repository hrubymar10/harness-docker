package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeTestConfig(t *testing.T, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "mcpbridge.jsonc")
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestReadConfigJSONCAndDefaults(t *testing.T) {
	path := writeTestConfig(t, `{
  // URLs inside strings are not comments.
  "servers": [{"name":"xcode", "command":"https://example.invalid/*", "enabled":false}],
  /* omitted listen and allow_list use safe defaults */
  "unknown-looking-string": "// not a comment"
}`)
	if _, err := readConfig(path); err == nil || !strings.Contains(err.Error(), "unknown field") {
		t.Fatalf("expected strict unknown-field error, got %v", err)
	}

	path = writeTestConfig(t, `{
  // line comment
  "servers": [{"name":"xcode", "command":"https://example.invalid/*"}]
}`)
	cfg, err := readConfig(path)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Listen != defaultListen {
		t.Fatalf("listen = %q, want %q", cfg.Listen, defaultListen)
	}
	if got := strings.Join(cfg.AllowList, ","); got != "127.0.0.0/8,::1/128" {
		t.Fatalf("allow_list = %q", got)
	}
	if enabledServerCount(cfg) != 1 {
		t.Fatalf("omitted enabled must default true")
	}
}

func TestReadConfigDisabledAndValidation(t *testing.T) {
	path := writeTestConfig(t, `{
  "listen":"127.0.0.1:9976",
  "allow_list":["127.0.0.1", "127.0.0.1/32"],
  "servers":[{"name":"xcode", "command":"xcrun", "enabled":false}]
}`)
	cfg, err := readConfig(path)
	if err != nil {
		t.Fatal(err)
	}
	if enabledServerCount(cfg) != 0 {
		t.Fatalf("disabled server counted as enabled")
	}

	cases := []string{
		`{"listen":"localhost:9976","servers":[]}`,
		`{"allow_list":[],"servers":[]}`,
		`{"allow_list":["localhost"],"servers":[]}`,
		`{"servers":[{"name":"bad.name","command":"x"}]}`,
		`{"servers":[{"name":"same","command":"x"},{"name":"same","command":"y"}]}`,
		`{"servers":[{"name":"empty","command":""}]}`,
		`{"servers":[],}`,
		`{/* unterminated`,
	}
	for _, body := range cases {
		if _, err := readConfig(writeTestConfig(t, body)); err == nil {
			t.Errorf("expected invalid config error for %s", body)
		}
	}
}

func TestParseAllowListNormalizesAndDeduplicates(t *testing.T) {
	got, err := parseAllowList([]string{"127.0.0.1", "127.0.0.1/32", "172.28.47.7/24", "::1"})
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"127.0.0.1/32", "172.28.47.0/24", "::1/128"}
	if len(got) != len(want) {
		t.Fatalf("got %v, want %v", got, want)
	}
	for i := range want {
		if got[i].String() != want[i] {
			t.Errorf("prefix %d = %s, want %s", i, got[i], want[i])
		}
	}
}
