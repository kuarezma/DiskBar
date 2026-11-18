package common

import "testing"

func TestIsVersionHigher(t *testing.T) {
	tests := []struct {
		remote  string
		current string
		want    bool
	}{
		{"v1.1.0", "1.0.0", true},
		{"v1.10.0", "v1.2.0", true},
		{"v2.0.0", "v1.9.9", true},
		{"v1.0.1", "1.0.0", true},
		{"1.0.0", "1.0.0", false},
		{"v1.0.0", "1.0.1", false},
		{"v1.2.0", "v1.10.0", false},
		{"1.1.0", "1.1.0-beta.1", true},
		{"1.1.0-beta.1", "1.1.0", false},
		{"1.1.0-beta.2", "1.1.0-beta.1", true},
		{"", "1.0.0", false},
		{"1.0.0", "", false},
	}

	for _, tc := range tests {
		got := IsVersionHigher(tc.remote, tc.current)
		if got != tc.want {
			t.Errorf("IsVersionHigher(%q, %q) = %v, want %v", tc.remote, tc.current, got, tc.want)
		}
	}
}

func TestFormatBytes(t *testing.T) {
	tests := []struct {
		in   uint64
		want string
	}{
		{0, "0 B"},
		{512, "512 B"},
		{1500, "1.5 KB"},
		{25_500_000, "25.5 MB"},
		{12_300_000_000, "12.3 GB"},
		{1_500_000_000_000, "1.50 TB"},
	}

	for _, tc := range tests {
		got := FormatBytes(tc.in)
		if got != tc.want {
			t.Errorf("FormatBytes(%d) = %q, want %q", tc.in, got, tc.want)
		}
	}
}
