package setup

import (
	"errors"
	"path/filepath"
	"regexp"
	"strings"
)

func validateDestination(base, root string) error {
	if !filepath.IsAbs(root) || filepath.Clean(root) != root {
		return errors.New("choose an absolute, canonical installation folder")
	}
	relative, e := filepath.Rel(base, root)
	if e != nil || relative == "." || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) || filepath.IsAbs(relative) {
		return errors.New("choose a dedicated folder under your Local AppData directory; administrator access is not required")
	}
	for _, part := range strings.Split(relative, string(filepath.Separator)) {
		if regexp.MustCompile(`(?i)^(CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])(?:\.|$)`).MatchString(part) || part == "" || strings.TrimRight(part, " .") != part || strings.ContainsAny(part, `:<>"|?*`) || strings.ContainsFunc(part, func(r rune) bool { return r < 32 }) {
			return errors.New("invalid Windows installation folder")
		}
	}
	return nil
}
