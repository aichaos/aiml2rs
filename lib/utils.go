package aiml2rs

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Die prints an error message (like fmt.Fprintf) to STDERR and exits
// with an error status.
func Die(tmpl string, x ...interface{}) {
	fmt.Fprintf(os.Stderr, tmpl+"\n", x...)
	os.Exit(1)
}

// Debug prints a debug message.
func (a *App) Debug(tmpl string, x ...interface{}) {
	if a.config.Debug {
		fmt.Printf(tmpl+"\n", x...)
	}
}

// ProcessFiles opens an input directory and processes all the files.
func (a *App) ProcessFiles(directory string, filetype string, handler func(string, *os.File) error) error {
	files, err := filepath.Glob(fmt.Sprintf("%s/*", directory))
	if err != nil {
		return err
	}

	for _, file := range files {
		// Check the file type.
		if !strings.HasSuffix(strings.ToLower(file), filetype) {
			continue
		}

		// Send it to the handler.
		fh, err := os.Open(file)
		if err != nil {
			return err
		}

		err = handler(file, fh)
		if err != nil {
			return err
		}

		// TODO
		break
	}

	return nil
}
