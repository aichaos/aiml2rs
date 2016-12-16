package aiml2rs

import "fmt"

// Type App is the main aiml2rs app receiver.
type App struct {
	config   *Config
	warnings []string
}

// New creates a new application.
func New(config *Config) *App {
	return &App{
		config:   config,
		warnings: []string{},
	}
}

// Run kicks off the app.
func (a *App) Run() {
	if a.config.Direction == ToRiveScript {
		a.aiml2rs()
	}
}

// warn adds a warning to the app's output.
func (a *App) warn(tmpl string, x ...interface{}) {
	a.warnings = append(a.warnings, fmt.Sprintf(tmpl, x...))
}
