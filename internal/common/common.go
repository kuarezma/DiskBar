package common

import (
	"fmt"
	"strconv"
	"strings"
)

const (
	LowSpaceThresholdBytes      uint64 = 10_000_000_000 // 10 GB (decimal)
	CriticalSpaceThresholdBytes uint64 = 5_000_000_000  // 5 GB (decimal)
)

// FormatBytes formats bytes using decimal SI units (KB=1000), matching macOS/DiskBar convention.
func FormatBytes(bytes uint64) string {
	const (
		KB = 1000
		MB = KB * 1000
		GB = MB * 1000
		TB = GB * 1000
	)
	switch {
	case bytes >= TB:
		return fmt.Sprintf("%.2f TB", float64(bytes)/float64(TB))
	case bytes >= GB:
		return fmt.Sprintf("%.1f GB", float64(bytes)/float64(GB))
	case bytes >= MB:
		return fmt.Sprintf("%.1f MB", float64(bytes)/float64(MB))
	case bytes >= KB:
		return fmt.Sprintf("%.1f KB", float64(bytes)/float64(KB))
	default:
		return fmt.Sprintf("%d B", bytes)
	}
}

// IsVersionHigher returns true if semantic version remote is strictly greater than current.
func IsVersionHigher(remote, current string) bool {
	r := strings.TrimSpace(strings.TrimLeft(remote, "vV"))
	c := strings.TrimSpace(strings.TrimLeft(current, "vV"))
	if r == "" || c == "" {
		return false
	}

	rBase, rPre, rHasPre := strings.Cut(r, "-")
	cBase, cPre, cHasPre := strings.Cut(c, "-")

	rParts := parseNumericParts(rBase)
	cParts := parseNumericParts(cBase)

	maxLen := len(rParts)
	if len(cParts) > maxLen {
		maxLen = len(cParts)
	}

	for i := 0; i < maxLen; i++ {
		rv, cv := 0, 0
		if i < len(rParts) {
			rv = rParts[i]
		}
		if i < len(cParts) {
			cv = cParts[i]
		}
		if rv > cv {
			return true
		}
		if rv < cv {
			return false
		}
	}

	// Stable release is higher than pre-release of the same base version.
	if rHasPre != cHasPre {
		return !rHasPre && cHasPre
	}
	if rHasPre && cHasPre {
		return rPre > cPre
	}
	return false
}

func parseNumericParts(base string) []int {
	raw := strings.Split(base, ".")
	parts := make([]int, len(raw))
	for i, p := range raw {
		n, err := strconv.Atoi(strings.TrimSpace(p))
		if err != nil {
			n = 0
		}
		parts[i] = n
	}
	return parts
}
