package main

import (
	"fmt"
	"log"
	"net/http"
	"net/netip"
	"strings"
)

func parseAllowList(entries []string) ([]netip.Prefix, error) {
	prefixes := make([]netip.Prefix, 0, len(entries))
	seen := make(map[netip.Prefix]bool)
	for _, raw := range entries {
		entry := strings.TrimSpace(raw)
		if entry == "" {
			return nil, fmt.Errorf("allow_list contains an empty entry")
		}
		var prefix netip.Prefix
		if strings.Contains(entry, "/") {
			parsed, err := netip.ParsePrefix(entry)
			if err != nil {
				return nil, fmt.Errorf("allow_list entry %q: %w", entry, err)
			}
			prefix = parsed.Masked()
		} else {
			addr, err := netip.ParseAddr(entry)
			if err != nil {
				return nil, fmt.Errorf("allow_list entry %q is not an IP or CIDR: %w", entry, err)
			}
			addr = addr.Unmap()
			bits := 32
			if addr.Is6() {
				bits = 128
			}
			prefix = netip.PrefixFrom(addr, bits)
		}
		if !seen[prefix] {
			seen[prefix] = true
			prefixes = append(prefixes, prefix)
		}
	}
	return prefixes, nil
}

func allowMiddleware(next http.Handler, allow []netip.Prefix) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		remote, err := netip.ParseAddrPort(r.RemoteAddr)
		if err != nil {
			log.Printf("WARN: blocked request with unparseable RemoteAddr %q: %v", r.RemoteAddr, err)
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		ip := remote.Addr().Unmap()
		for _, prefix := range allow {
			if prefix.Contains(ip) {
				next.ServeHTTP(w, r)
				return
			}
		}
		log.Printf("WARN: blocked %s — not in allow_list", ip)
		http.Error(w, "forbidden", http.StatusForbidden)
	})
}
