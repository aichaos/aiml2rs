package aiml2rs

import (
	"bytes"
	"encoding/xml"
	"fmt"
	"log"
	"os"
	"path"
	"regexp"
	"strings"
)

var OldGetTag = regexp.MustCompile(`^get_(.+?)$`)
var TriggerSyntaxError = regexp.MustCompile(`[^A-Za-z0-9<>\{\}= \*_\#\(\)\[\]]`)
var HTMLBreak = regexp.MustCompile(`<br.+?>`)

// Tags that we're purposely ignoring (so we don't give warnings about
// unhandled tags while parsing the AIML).
var IgnoreTags = []string{
	// Common HTML
	"a", "b", "i", "br", "ul", "p", "li", "em", "img",

	// AIML tags we're not supporting
	"eval", "learn",

	// Pandorabots tags we're not supporting
	"oob", "dial", "dialcontact", "map", "search", "sms", "recipient",
	"message",
}

// Type AIMLState tracks temporary parsing state for AIML files.
type AIMLState struct {
	Topic         string    // The current <topic> being parsed (default "random")
	Buffer        string    // Current text buffer for {pattern,that,template,...}
	InTag         string    // Inside a container tag like <pattern>, <that>, etc.
	Category      *Category // The current category buffer, until </category>
	Thinking      bool      // Inside a <think> tag
	SetName       string    // The variable named in a <set name="x"> tag.
	SetValue      string    // The text for setting a variable.
	InRandom      bool      // Inside a <random> tag.
	Random        []string  // Buffer for <li>'s within a <random>
	InCondition   bool      // Inside a <condition> tag.
	ConditionName string    // Condition name (<condition name="x">)
	Conditions    []string  // The conditions
	Tainted       bool      // Reply is too complicated for RiveScript to support (i.e., embedded <random>)
}

func NewAIMLState() *AIMLState {
	return &AIMLState{
		Topic:      "random",
		Category:   &Category{},
		Random:     []string{},
		Conditions: []string{},
	}
}

// Type Category contains state information for an AIML category.
type Category struct {
	Pattern    string
	That       string
	Template   string
	Conditions []string
}

func NewCategory() *Category {
	return &Category{
		Conditions: []string{},
	}
}

// Type ParsedAIML holds parsed AIML data.
type ParsedAIML struct {
	Topics map[string][]*Category
}

// aiml2rs converts AIML code into RiveScript code.
func (a *App) aiml2rs() {
	err := a.ProcessFiles(a.config.Input, ".aiml", a.processAIML)
	if err != nil {
		Die("Error processing AIML files: %s", err)
	}
}

// processAIML processes an AIML file.
func (a *App) processAIML(file string, fh *os.File) error {
	log.Printf("Processing: %s\n", file)

	var (
		token xml.Token
		err   error
	)

	// Initialize the state.
	state := NewAIMLState()

	// Structure of parsed categories.
	parsed := &ParsedAIML{
		Topics: map[string][]*Category{},
	}

	// Parse the XML file a token at a time.
	parser := xml.NewDecoder(fh)
	for {
		token, err = parser.Token()
		if err != nil && err.Error() != "EOF" {
			return err
		}

		// Quit at the end of the file.
		if token == nil {
			break
		}

		// What kind of token is this?
		var event rune
		var tag string
		switch token.(type) {
		case xml.CharData:
			event = 'T'
		case xml.StartElement:
			event = 'S'
			tag = strings.ToLower(token.(xml.StartElement).Name.Local)
		case xml.EndElement:
			event = 'E'
			tag = strings.ToLower(token.(xml.EndElement).Name.Local)
		default:
			continue
		}

		/*
			The parsing logic below is confusing, but let me explain what it's
			trying to do.

			I only care about two types of XML tokens: CharData (text), and
			tags (Opening & Closing).

			CharData is easy to handle -- it's just plain text, so I just have to
			put that text in the correct buffer depending on what tags we're
			inside of:

			* <set>...</set>             => Goes into the state.SetValue
			* <random>...</random>       => Goes into state.Random
			* <condition>...</condition> => Goes into state.Conditions
			* Else it goes into state.Buffer.

			The complicated part is the Tag Handling.

			First, I do a big if/else if/else block to handle the AIML tags that
			require special treatment. Generally, these tags fall into two
			categories: tags that get replaced by RiveScript versions of them,
			or tags that change the parser state (have no echo in RiveScript).

			A tag that changes the parser state (examples: <topic>, <think>,
			<condition>) does its job and then does `continue` to progress the
			main parser loop. The `continue` is important!!!

			A tag that replaces itself with a RiveScript equivalent, on the other
			hand, puts its replacement text into the `newText` variable, and
			the code continues past the `else` statement (does not `continue`!)

			This brings us to the code that follows AFTER the tag handling
			blocks. This code is only hit by the tags that set `newText`, or when
			an unknown XML tag was seen (could be HTML code!) that wasn't
			specifically handled. In that case, the `newText` is set to the literal
			XML tag, so that HTML and such can be preserved untainted.

			This footer block of code is responsible for adding whatever's in
			`newText` into the right buffer. Just like when we handled the plain
			CharData tokens, the content of `newText` can be put into the
			`<set>`, `<random>`, `<condition>`, or text buffers.

			This logic is a bit weird but it's because the aforementioned tags
			can contain text *and other tags*, and it's those other tags that
			makes this difficult. So the footer takes all the leftover data from
			the XML (literal AIML tags or substituted RiveScript tags) and still
			puts them in the right spots as-is.
		*/

		// Many tags want to add some buffer text. This will be handled at
		// the end of this loop in the 'else' case.
		var newText string

		if event == 'T' {
			// A text node.
			node := token.(xml.CharData)
			text := strings.TrimSpace(string([]byte(node)))
			if len(text) == 0 {
				continue
			}

			// TODO: the space trimming can be overzealous and cause
			// text to directly touch following tags.

			// Are we inside a tag?
			if state.SetName != "" {
				// Inside <set>...</set>
				state.SetValue += text
			} else if state.InRandom {
				if len(state.Random) == 0 {
					state.Random = append(state.Random, "")
				}
				state.Random[len(state.Random)-1] += text
			} else if state.InCondition {
				state.Conditions[len(state.Conditions)-1] += text
			} else {
				state.Buffer += text
			}
		} else {
			// An XML tag.
			var node xml.StartElement
			if event == 'S' {
				node = token.(xml.StartElement)
			}

			a.Debug("[%s] %s", string(event), tag)

			if tag == "aiml" {
				continue
			} else if tag == "topic" {
				if event == 'S' && a.config.RealTopics {
					state.Topic = attr(node, "name")
					a.Debug("Set RiveScript topic to %s", state.Topic)
				}
				continue
			} else if tag == "category" {
				// <category>...</category>
				if event == 'S' {
					state.Category = NewCategory()
					state.Tainted = false
				} else {
					if state.Tainted {
						// We can't handle this category in RiveScript.
						a.Debug("Category was tainted! Skipping!")
						continue
					}

					// Initialize this topic?
					if _, ok := parsed.Topics[state.Topic]; !ok {
						parsed.Topics[state.Topic] = []*Category{}
					}

					// Conditions?
					if len(state.Conditions) > 0 {
						state.Category.Conditions = state.Conditions
						state.Conditions = []string{}
					}

					parsed.Topics[state.Topic] = append(parsed.Topics[state.Topic], state.Category)
				}
				continue
			} else if tag == "pattern" || tag == "that" || tag == "template" {
				// Significant container tag.
				if event == 'S' {
					state.InTag = tag
					state.Buffer = ""
				} else {
					// Fix AIML _ wildcards.
					if tag == "pattern" && strings.Index(state.Buffer, "_") > -1 {
						state.Buffer = strings.Replace(state.Buffer, "_", "*", -1)
					}

					if tag == "pattern" {
						state.Category.Pattern = state.Buffer
					} else if tag == "that" {
						state.Category.That = state.Buffer
					} else if tag == "template" {
						state.Category.Template = state.Buffer
					}
				}
				continue
			} else if tag == "think" {
				// The <think> tag, controls whether <set>'s need to be echoed back
				state.Thinking = event == 'S'
				continue
			} else if tag == "star" || tag == "input" || tag == "request" || tag == "response" {
				// <star>, <input>, <request>, <response>
				if event == 'S' {
					// Translate it to the RiveScript version.
					rs := tag
					if tag == "response" {
						rs = "reply"
					} else if tag == "request" {
						rs = "input"
					}

					// Get the index attribute if possible.
					index := attr(node, "index")
					if index == "" {
						index = "1"
					}

					// Make the final RiveScript tag.
					text := fmt.Sprintf("<%s%s>", rs, index)
					if index == "1" {
						text = fmt.Sprintf("<%s>", rs)
					}

					newText = text
				} else {
					continue
				}
			} else if tag == "id" {
				if event == 'S' {
					newText = "<id>"
				} else {
					continue
				}
			} else if tag == "bot" || tag == "get" || strings.Index(tag, "get_") > -1 {
				// <bot name="x"/>, <get name="x"/>, <get_name/>
				if event == 'S' {
					name := attr(node, "name")

					// Old-style <get> tag?
					match := OldGetTag.FindStringSubmatch(tag)
					if len(match) > 0 {
						tag = "get"
						name = match[1]
					}

					if len(name) > 0 {
						newText = fmt.Sprintf("<%s %s>", tag, name)
					}
				} else {
					continue
				}
			} else if tag == "set" {
				// <set>
				if event == 'S' {
					// Get the name of it.
					state.SetName = attr(node, "name")
					state.SetValue = ""
					a.Debug("Found opening <set> tag for name=%s", state.SetName)
					continue
				} else {
					// The tag is completed.
					if len(state.SetName) == 0 {
						continue
					}

					// Alice topics? Avoid clashing with RS topics.
					if state.SetName == "topic" && !a.config.RealTopics {
						state.SetName = "alicetopic"
					}

					// Special hack to formalize names.
					if state.SetName == "name" {
						state.SetValue = fmt.Sprintf("{formal}%s{/formal}", state.SetValue)
					}

					// Delete if blank.
					if state.SetValue == "" || state.SetValue == "{formal}{/formal}" {
						state.SetValue = "<undef>"
					}

					newText = fmt.Sprintf("<set %s=%s>", state.SetName, state.SetValue)

					// Echo it back immediately unless in <think>.
					if !state.Thinking {
						newText += fmt.Sprintf("<get %s>", state.SetName)
					}

					a.Debug("End <set> tag with buffer: %s", newText)

					// Clear the set buffers.
					state.SetName = ""
					state.SetValue = ""
				}
			} else if tag == "random" {
				// <random>
				if event == 'S' {
					// Begin the random buffer.
					if state.InRandom {
						a.warn("Embedded randoms at %s in pattern %s",
							file,
							state.Category.Pattern,
						)
						state.Tainted = true
					}
					state.InRandom = true
					state.Random = []string{}
					continue
				} else {
					// Join the random bits.
					var random []string
					for _, item := range state.Random {
						item = strings.TrimSpace(item)
						if len(item) == 0 {
							continue
						}
						random = append(random, item)
					}

					text := strings.Join(random, "|")
					newText = fmt.Sprintf("{random}%s{/random}", text)

					// Reset the state buffers.
					state.InRandom = false
					state.Random = []string{}
				}
			} else if tag == "condition" {
				// <condition>
				if event == 'S' {
					// We only bother with super simple conditions that follow this pattern:
					// <template>
					//  <condition name="x">
					//   <li value="y">...</li>
					//  </condition>
					// </template>
					state.InCondition = true
					state.ConditionName = attr(node, "name")
					state.Conditions = []string{}
				} else {
					state.InCondition = false
					state.ConditionName = ""
					state.Conditions = []string{}
				}
				continue
			} else if tag == "li" {
				// <li> can be a part of <random> or <condition>
				if state.InRandom {
					if event == 'S' {
						// New random buffer.
						state.Random = append(state.Random, "")
					}
				} else if state.InCondition {
					// In a condition. Prefer the name from the <condition>
					// tag, but check the <li name="x"> attribute too.
					name := state.ConditionName
					liName := attr(node, "name")
					if liName != "" {
						name = liName
					}

					// No name?
					if name == "" {
						a.warn("Condition too complicated to handle at %s in pattern %s", file, state.Category.Pattern)
						continue
					}

					value := attr(node, "value")
					if value != "" {
						// Handle special values.
						if strings.ToLower(value) == "unknown" {
							value = "undefined"
						}
						if strings.ToLower(value) == "om" {
							// Alice's brain had this weird thing.
							value = "undefined"
						}

						if value == "*" {
							// * = not undefined
							state.Conditions = append(state.Conditions, fmt.Sprintf("<get %s> != undefined => ", name))
						} else {
							state.Conditions = append(state.Conditions, fmt.Sprintf("<get %s> == %s => ", name, value))
						}
					} else {
						state.InCondition = false
					}
				}
				continue
			} else if tag == "srai" {
				// <srai> tag.
				if event == 'S' {
					newText = "{@"
				} else {
					newText = "}"
				}
			} else if tag == "sr" || tag == "person" {
				// <sr/>, <person/>
				if event == 'S' {
					if tag == "sr" {
						newText = "<@>"
					} else {
						newText = "<person>"
					}
				}
			} else if tag == "uppercase" || tag == "lowercase" || tag == "formal" || tag == "sentence" {
				// <uppercase>, <lowercase>, <formal>, <sentence>
				if event == 'S' {
					newText = fmt.Sprintf("{%s}", tag)
				} else {
					newText = fmt.Sprintf("{/%s}", tag)
				}
			} else if tag == "date" || tag == "size" {
				// Alice special tags <date> and <size>
				if event == 'S' {
					var args string
					if tag == "date" {
						format := attr(node, "format")
						if format != "" {
							args = " " + format
						}
					}
					newText = fmt.Sprintf("<call>%s%s</call>", tag, args)
				}
			}

			// NOTE: Tags that changed the parser state but have no echo
			// in RiveScript will have `continue`d the loop earlier, and
			// the code doesn't get to this point. If this code is
			// executing, it means we've either set `newText` to be a
			// RiveScript equivalent of an AIML tag, or we're on an
			// unknown XML tag (could be HTML, who knows) that didn't get
			// specifically handled above.
			//
			// If we're here and we don't have any `newText`, it's assumed
			// that it was an unknown tag so we reproduce the literal XML
			// tag, and use *that* as our `newText`.

			// New text buffer given above?
			var handled bool
			if len(newText) == 0 {
				// Nope, then add this tag verbatim.
				newText = rawXML(token)
			} else {
				handled = true
			}

			// All the other tags that have children.
			if len(state.SetName) > 0 {
				a.Debug("In <set> tag: appending %s", newText)
				state.SetValue += newText
			} else if state.InRandom {
				if len(state.Random) == 0 {
					state.Random = append(state.Random, "")
				}
				state.Random[len(state.Random)-1] += newText
			} else if state.InCondition {
				if len(state.Conditions) > 0 {
					state.Conditions[len(state.Conditions)-1] += newText
				}
			} else {
				state.Buffer += newText
			}

			// Log about any unhandled AIML tags, skipping common HTML
			// ones.
			var skipWarning bool
			for _, ignore := range IgnoreTags {
				if tag == ignore {
					skipWarning = true
					break
				}
			}

			if handled || skipWarning {
				continue
			}
			a.warn("Unhandled AIML tag: %s", rawXML(token))
		}
	}

	a.WriteRiveScript(file, parsed)

	return nil
}

// WriteRiveScript writes the RiveScript output file.
func (a *App) WriteRiveScript(file string, parsed *ParsedAIML) {
	// Get the base name of the file and rename it to '.rive'
	file = strings.Replace(path.Base(file), ".aiml", ".rive", -1)

	// Open it for writing.
	fh, err := os.Create(fmt.Sprintf("%s/%s", a.config.Output, file))
	if err != nil {
		panic(err)
	}
	defer fh.Close()
	fh.WriteString("// Converted using aiml2rs.go\n") // TODO: date
	fh.WriteString("! version = 2.0\n\n")

	for topic, categories := range parsed.Topics {
		if topic != "random" {
			fh.WriteString(fmt.Sprintf("> topic %s\n\n", topic))
		}

		for _, category := range categories {
			// TODO: Skip if this whole category was just a full redirect.

			trigger := strings.ToLower(category.Pattern)

			// Skip triggers with syntax errors.
			match := TriggerSyntaxError.FindStringSubmatch(trigger)
			if len(match) > 0 {
				a.warn("Trigger '%s' has syntax errors. Skipping.", trigger)
				continue
			}
			fh.WriteString(fmt.Sprintf("+ %s\n", trigger))

			// TODO: aliases

			if len(category.That) > 0 {
				that := strings.ToLower(category.That)
				that = TriggerSyntaxError.ReplaceAllLiteralString(that, "")
				fh.WriteString(fmt.Sprintf("%% %s\n", that))
			}

			// Conditions.
			if len(category.Conditions) > 0 {
				for _, c := range category.Conditions {
					c = strings.Replace(c, "\n", "\\n", -1)
					c = HTMLBreak.ReplaceAllLiteralString(c, "\n")
					c = strings.TrimSpace(c)
					fh.WriteString(fmt.Sprintf("* %s\n", c))
				}
			}

			template := category.Template
			template = strings.Replace(template, "\n", "\\n", -1)
			template = HTMLBreak.ReplaceAllLiteralString(template, "\n")
			template = strings.TrimSpace(template)

			fh.WriteString(fmt.Sprintf("- %s\n\n", template))
		}

		if topic != "random" {
			fh.WriteString("< topic\n\n")
		}
	}
}

// attr gets an XML attribute from an XML node.
func attr(node xml.StartElement, name string) string {
	for _, attr := range node.Attr {
		if strings.ToLower(attr.Name.Local) == name {
			return attr.Value
		}
	}
	return ""
}

// rawXML reconstructs an XML tag from its token.
func rawXML(token xml.Token) string {
	buf := bytes.NewBuffer([]byte{})
	buf.WriteRune('<')

	switch token.(type) {
	case xml.StartElement:
		node := token.(xml.StartElement)
		buf.WriteString(node.Name.Local)
		if len(node.Attr) > 0 {
			buf.WriteRune(' ')
			for i, attr := range node.Attr {
				buf.WriteString(fmt.Sprintf(`%s="%s"`, attr.Name.Local, attr.Value))
				if i < len(node.Attr)-1 {
					buf.WriteRune(' ')
				}
			}
		}
	case xml.EndElement:
		node := token.(xml.EndElement)
		buf.WriteRune('/')
		buf.WriteString(node.Name.Local)
	}

	buf.WriteRune('>')
	return buf.String()
}
