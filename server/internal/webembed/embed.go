package webembed

import (
	"embed"
	"io/fs"
	"net/http"
	"strings"
)

//go:embed all:static
var staticFS embed.FS

// Handler serves embedded web UI. HTML at /, assets under /assets/.
func Handler() http.Handler {
	sub, err := fs.Sub(staticFS, "static")
	if err != nil {
		panic(err)
	}
	fileServer := http.FileServer(http.FS(sub))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p := r.URL.Path
		if p == "/assets" || strings.HasPrefix(p, "/assets/") {
			r2 := r.Clone(r.Context())
			r2.URL.Path = strings.TrimPrefix(p, "/assets")
			if r2.URL.Path == "" {
				r2.URL.Path = "/"
			}
			fileServer.ServeHTTP(w, r2)
			return
		}
		// map / -> index.html, /release.html etc.
		fileServer.ServeHTTP(w, r)
	})
}
