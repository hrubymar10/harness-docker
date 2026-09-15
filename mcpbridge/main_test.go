package main

import "testing"

func TestRunConfiguredExitCodes(t *testing.T) {
	enabled := writeTestConfig(t, `{"servers":[{"name":"fake","command":"fake"}]}`)
	empty := writeTestConfig(t, `{"servers":[]}`)
	invalid := writeTestConfig(t, `{"servers":[}`)

	for _, tc := range []struct {
		name string
		args []string
		want int
	}{
		{"enabled", []string{"configured", "--config", enabled}, 0},
		{"empty", []string{"configured", "--config", empty}, 1},
		{"invalid", []string{"configured", "--config", invalid}, 2},
		{"missing flag", []string{"configured", enabled}, 2},
		{"unknown mode", []string{"unknown", "--config", enabled}, 2},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := run(tc.args); got != tc.want {
				t.Fatalf("run(%q) = %d, want %d", tc.args, got, tc.want)
			}
		})
	}
}
