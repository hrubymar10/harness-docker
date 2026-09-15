package main

import (
	"net/http"
	"net/http/httptest"
	"net/netip"
	"testing"
)

func TestAllowMiddleware(t *testing.T) {
	allow := []netip.Prefix{
		netip.MustParsePrefix("127.0.0.0/8"),
		netip.MustParsePrefix("172.28.47.0/24"),
		netip.MustParsePrefix("::1/128"),
	}
	handler := allowMiddleware(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}), allow)
	cases := []struct {
		remote string
		want   int
	}{
		{"127.0.0.1:1", http.StatusNoContent},
		{"172.28.47.99:2", http.StatusNoContent},
		{"[::1]:3", http.StatusNoContent},
		{"[::ffff:127.0.0.1]:4", http.StatusNoContent},
		{"10.0.0.1:5", http.StatusForbidden},
		{"not-an-address", http.StatusForbidden},
	}
	for _, tc := range cases {
		req := httptest.NewRequest(http.MethodGet, "/health", nil)
		req.RemoteAddr = tc.remote
		recorder := httptest.NewRecorder()
		handler.ServeHTTP(recorder, req)
		if recorder.Code != tc.want {
			t.Errorf("remote %q: got %d, want %d", tc.remote, recorder.Code, tc.want)
		}
	}
}
