package aiml2rs

const (
	ToAIML       = true
	ToRiveScript = false
)

// Type Config carries command line settings for the application.
type Config struct {
	Debug      bool
	Direction  bool   // ToAIML or ToRiveScript
	RealTopics bool   // Convert AIML <topic> into real RiveScript topics
	Input      string // Input directory
	Output     string // Output directory
}
