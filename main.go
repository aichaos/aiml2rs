package main

import (
	"flag"
	"fmt"
	"log"
	"os"

	"github.com/aichaos/aiml2rs/lib"
)

var (
	// Command line options.
	toAIML          bool
	toRS            bool
	inputDirectory  string
	outputDirectory string
	showVersion     bool
	realTopics      bool
	debug           bool
)

func init() {
	// Command line parameters.
	flag.BoolVar(&toAIML, "aiml", false, "Convert from RiveScript to AIML")
	flag.BoolVar(&toRS, "rs", false, "Convert from AIML to RiveScript")
	flag.StringVar(&inputDirectory, "in", "", "Directory of input files")
	flag.StringVar(&outputDirectory, "out", "", "Directory for output files (will be created if it doesn't exist)")
	flag.BoolVar(&realTopics, "real-topics", false, "Use real topics in RiveScript output when converting AIML <topic> tags")
	flag.BoolVar(&showVersion, "v", false, "Show the version number of aiml2rs")
	flag.BoolVar(&debug, "debug", false, "Enable debug mode")
}

func main() {
	flag.Parse()
	validateFlags()

	// Configuration.
	app := aiml2rs.New(&aiml2rs.Config{
		Debug:      debug,
		Direction:  toAIML, // true = AIML, false = RiveScript
		RealTopics: realTopics,
		Input:      inputDirectory,
		Output:     outputDirectory,
	})
	app.Run()
}

// validateFlags checks all the input parameters.
func validateFlags() {
	// The version flag `-v` prints the version and exits.
	if showVersion {
		fmt.Printf("This is aiml2rs version v%s\n", aiml2rs.VERSION)
		os.Exit(0)
	}

	// One of the conversion directions is required.
	if !toAIML && !toRS {
		usage()
	}

	// The directions are mutually exclusive.
	if toAIML && toRS {
		aiml2rs.Die("The -aiml and -rs options are mutually exclusive")
	}

	// The directory options must be defined.
	if inputDirectory == "" || outputDirectory == "" {
		aiml2rs.Die("Missing required parameters `-in` and `-out`")
	}

	// The input path must be a directory.
	if !isDirectory(inputDirectory) {
		aiml2rs.Die("%s is not a directory", inputDirectory)
	}

	// The output path should either not exist, or be a directory.
	stat, err := os.Stat(outputDirectory)
	if err == nil && !stat.IsDir() {
		// No error means the thing exists, and we know it's not a directory.
		aiml2rs.Die("%s exists but is not a directory", outputDirectory)
	} else {
		// An error means it doesn't exist, so create it.
		log.Printf("Creating output directory: %s", outputDirectory)
		err = os.MkdirAll(outputDirectory, 0755)
		if err != nil {
			aiml2rs.Die("Error creating output directory: %s", err)
		}
	}
}

// usage prints the usage info and quits.
func usage() {
	fmt.Printf(`aiml2rs v%s

This program converts AIML code into RiveScript, and vice versa.

To convert AIML to RiveScript:
    aiml2rs -aiml -in /path/to/aiml/files -out /output/rivescript/files

To convert RiveScript to AIML:
    aiml2rs -rs -in /path/to/rivescript/files -out /output/aiml/files

See 'aiml2rs -h' for full command usage.
`, aiml2rs.VERSION)
	os.Exit(1)
}

// isDirectory checks if a file path is a directory.
func isDirectory(path string) bool {
	info, err := os.Stat(path)
	if err != nil {
		return false
	}
	return info.IsDir()
}
