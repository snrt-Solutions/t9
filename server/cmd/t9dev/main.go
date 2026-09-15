package main

import (
	"bufio"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
	"unicode/utf8"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	switch os.Args[1] {
	case "login":
		must(cmdLogin())
	case "fetch":
		must(cmdFetch())
	case "send":
		must(cmdSend())
	case "info":
		must(cmdInfo())
	default:
		usage()
		os.Exit(2)
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, `t9dev — local stand-in for the signed iOS app

  t9dev info
  t9dev login
  t9dev fetch
  t9dev send -to USER -text "hello"

Env:
  T9_URL   default http://127.0.0.1:8080
  T9_USER  username (login)
  T9_PASS  password (login; otherwise prompted)
  T9_HOME  token dir, default ~/.t9dev
`)
}

func baseURL() string {
	u := strings.TrimRight(envOr("T9_URL", "http://127.0.0.1:8080"), "/")
	return u
}

func home() string {
	if h := os.Getenv("T9_HOME"); h != "" {
		return h
	}
	d, _ := os.UserHomeDir()
	return filepath.Join(d, ".t9dev")
}

func tokenPath() string { return filepath.Join(home(), "device_token") }

func saveToken(tok string) error {
	if err := os.MkdirAll(home(), 0o700); err != nil {
		return err
	}
	return os.WriteFile(tokenPath(), []byte(tok+"\n"), 0o600)
}

func loadToken() (string, error) {
	b, err := os.ReadFile(tokenPath())
	if err != nil {
		return "", fmt.Errorf("no device token — run: t9dev login")
	}
	return strings.TrimSpace(string(b)), nil
}

func cmdInfo() error {
	var out map[string]any
	if err := getJSON("/v1/info", "", &out); err != nil {
		return err
	}
	printJSON(out)
	return nil
}

func cmdLogin() error {
	user := envOr("T9_USER", flagVal("-user"))
	if user == "" {
		user = prompt("username: ", false)
	}
	pass := envOr("T9_PASS", flagVal("-pass"))
	if pass == "" {
		pass = prompt("password: ", true)
	}
	deviceID := envOr("T9_DEVICE", "t9dev-"+hostname())
	body, err := postJSON("/v1/device/login", "", map[string]any{
		"username":  user,
		"password":  pass,
		"device_id": deviceID,
		"assertion": "t9-ios-mvp-signed-placeholder",
	})
	if err != nil {
		return err
	}
	pending, _ := body["pending_id"].(string)
	rel, _ := body["release_url"].(string)
	fmt.Printf("pending_id: %s\n", pending)
	fmt.Printf("Open this URL, enter username + TOTP, Approve:\n  %s\n", rel)
	fmt.Println("Waiting for web release…")
	for i := 0; i < 120; i++ {
		time.Sleep(2 * time.Second)
		var poll map[string]any
		if err := getJSON("/v1/device/login/"+pending, "", &poll); err != nil {
			return err
		}
		st, _ := poll["status"].(string)
		fmt.Printf("  status=%s\n", st)
		if tok, _ := poll["device_token"].(string); tok != "" {
			if err := saveToken(tok); err != nil {
				return err
			}
			fmt.Printf("device token saved to %s\n", tokenPath())
			return nil
		}
		if st == "denied" {
			return fmt.Errorf("denied on web")
		}
	}
	return fmt.Errorf("timed out waiting for release")
}

func cmdFetch() error {
	tok, err := loadToken()
	if err != nil {
		return err
	}
	var out map[string]any
	if err := getJSON("/v1/messages", tok, &out); err != nil {
		return err
	}
	printJSON(out)
	return nil
}

func cmdSend() error {
	to := flagVal("-to")
	text := flagVal("-text")
	if to == "" || text == "" {
		return fmt.Errorf("usage: t9dev send -to USER -text \"hello\"")
	}
	n := utf8.RuneCountInString(text)
	if n < 1 || n > 160 {
		return fmt.Errorf("text must be 1..160 runes, got %d", n)
	}
	tok, err := loadToken()
	if err != nil {
		return err
	}
	ct := base64.StdEncoding.EncodeToString([]byte(text))
	body, err := postJSON("/v1/messages", tok, map[string]any{
		"to_username": to,
		"ciphertext":  ct,
		"graphemes":   n,
	})
	if err != nil {
		return err
	}
	printJSON(body)
	return nil
}

func flagVal(name string) string {
	for i, a := range os.Args {
		if a == name && i+1 < len(os.Args) {
			return os.Args[i+1]
		}
	}
	return ""
}

func envOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func hostname() string {
	h, _ := os.Hostname()
	if h == "" {
		return "local"
	}
	return h
}

func prompt(label string, hide bool) string {
	fmt.Fprint(os.Stderr, label)
	if hide {
		fmt.Fprint(os.Stderr, "(visible) ")
	}
	s, _ := bufio.NewReader(os.Stdin).ReadString('\n')
	return strings.TrimSpace(s)
}

func getJSON(path, token string, dest any) error {
	req, err := http.NewRequest(http.MethodGet, baseURL()+path, nil)
	if err != nil {
		return err
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	return doJSON(req, dest)
}

func postJSON(path, token string, payload map[string]any) (map[string]any, error) {
	b, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequest(http.MethodPost, baseURL()+path, strings.NewReader(string(b)))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	var out map[string]any
	if err := doJSON(req, &out); err != nil {
		return nil, err
	}
	return out, nil
}

func doJSON(req *http.Request, dest any) error {
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(res.Body, 1<<20))
	if res.StatusCode >= 400 {
		return fmt.Errorf("%s: %s", res.Status, strings.TrimSpace(string(raw)))
	}
	if dest == nil || len(raw) == 0 {
		return nil
	}
	return json.Unmarshal(raw, dest)
}

func printJSON(v any) {
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	_ = enc.Encode(v)
}

func must(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
