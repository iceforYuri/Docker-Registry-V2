package registry

import (
	"regexp"
)

var DigestRegex = regexp.MustCompile(`^sha256:[a-f0-9]{64}$`)
