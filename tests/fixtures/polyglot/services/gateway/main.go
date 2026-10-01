package main

import (
	"net/http"
	"os"

	"github.com/go-chi/chi/v5"
)

func main() {
	r := chi.NewRouter()
	r.Route("/v1", func(r chi.Router) {
		r.Get("/items", listItems)
	})
	http.ListenAndServe(":"+os.Getenv("PORT"), r)
}

func listItems(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(200) }
