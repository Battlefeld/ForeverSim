// ForeverCore overlay. Not part of the upstream engine.
package cmd

import "os"

// foreverCoreStrict makes the sim command refuse a request with a field the engine does not know, instead of dropping
// it: ForeverCore builds its requests by hand, and a misspelt field would otherwise change nothing without a word.
// ForeverCore sets FOREVERCORE_STRICT for every run; without it the engine reads requests as upstream does.
func foreverCoreStrict() bool { return os.Getenv("FOREVERCORE_STRICT") != "" }
