package indexer

import (
	"slices"
	"testing"

	"github.com/asciimoo/hister/server/document"
	"github.com/asciimoo/hister/server/testutil"
)

func TestSearchOnlyNegatedTerms(t *testing.T) {
	idxCfg := testutil.Config(t)
	if err := Init(idxCfg); err != nil {
		t.Fatalf("failed to init indexer: %v", err)
	}
	defer i.Close()

	documents := []*document.Document{
		{URL: "https://go.dev/doc", Title: "Golang docs", Text: "golang language"},
		{URL: "https://rust-lang.org/", Title: "Rust", Text: "rust language"},
		{URL: "https://python.org/", Title: "Python", Text: "python language"},
	}
	for _, d := range documents {
		if err := Add(d); err != nil {
			t.Fatalf("Add(%q): %v", d.URL, err)
		}
	}

	for _, tc := range []struct {
		query string
		want  []string
	}{
		{"-title:golang", []string{documents[1].URL, documents[2].URL}},
		{"-golang", []string{documents[1].URL, documents[2].URL}},
		{`-"golang language"`, []string{documents[1].URL, documents[2].URL}},
		{"-golang -python", []string{documents[1].URL}},
		{"language -golang", []string{documents[1].URL, documents[2].URL}},
	} {
		t.Run(tc.query, func(t *testing.T) {
			res, err := Search(idxCfg, &Query{Text: tc.query})
			if err != nil {
				t.Fatalf("Search(%q): %v", tc.query, err)
			}
			got := make([]string, 0, len(res.Documents))
			for _, d := range res.Documents {
				got = append(got, d.URL)
			}
			slices.Sort(got)
			want := slices.Clone(tc.want)
			slices.Sort(want)
			if !slices.Equal(got, want) {
				t.Errorf("Search(%q) URLs = %q, want %q", tc.query, got, want)
			}
		})
	}
}

func TestSearchSortsByMostVisited(t *testing.T) {
	idxCfg := testutil.Config(t)
	if err := Init(idxCfg); err != nil {
		t.Fatalf("failed to init indexer: %v", err)
	}
	defer i.Close()

	lessVisitedURL := "https://example.com/less-visited"
	mostVisitedURL := "https://example.com/most-visited"
	docs := []string{
		lessVisitedURL,
		mostVisitedURL,
		mostVisitedURL,
		mostVisitedURL,
	}
	for _, url := range docs {
		if err := Add(&document.Document{
			URL:   url,
			Title: "Visited sort",
			Text:  "Visited sort document text",
		}); err != nil {
			t.Fatalf("Add failed: %v", err)
		}
	}

	res, err := Search(idxCfg, &Query{Text: "*", Sort: "visits"})
	if err != nil {
		t.Fatalf("Search failed: %v", err)
	}
	if len(res.Documents) < 2 {
		t.Fatalf("Search returned %d documents, want at least 2", len(res.Documents))
	}
	if res.Documents[0].URL != mostVisitedURL {
		t.Fatalf("first result URL = %q, want %q", res.Documents[0].URL, mostVisitedURL)
	}
	if res.Documents[0].AddCount != 3 {
		t.Fatalf("first result AddCount = %d, want 3", res.Documents[0].AddCount)
	}
	if res.Documents[1].URL != lessVisitedURL {
		t.Fatalf("second result URL = %q, want %q", res.Documents[1].URL, lessVisitedURL)
	}
}

func TestSearchFiltersByVisitCount(t *testing.T) {
	idxCfg := testutil.Config(t)
	if err := Init(idxCfg); err != nil {
		t.Fatalf("failed to init indexer: %v", err)
	}
	defer i.Close()

	lessVisitedURL := "https://example.com/visit-filter-less"
	mostVisitedURL := "https://example.com/visit-filter-most"
	docs := []string{
		lessVisitedURL,
		mostVisitedURL,
		mostVisitedURL,
		mostVisitedURL,
	}
	for _, url := range docs {
		if err := Add(&document.Document{
			URL:   url,
			Title: "Visited filter",
			Text:  "Visited filter document text",
		}); err != nil {
			t.Fatalf("Add failed: %v", err)
		}
	}

	res, err := Search(idxCfg, &Query{Text: "Visited filter visits:2..4"})
	if err != nil {
		t.Fatalf("Search failed: %v", err)
	}
	if len(res.Documents) != 1 {
		t.Fatalf("Search returned %d documents, want 1", len(res.Documents))
	}
	if res.Documents[0].URL != mostVisitedURL {
		t.Fatalf("result URL = %q, want %q", res.Documents[0].URL, mostVisitedURL)
	}
}

func TestSearchVisitCountFacets(t *testing.T) {
	idxCfg := testutil.Config(t)
	if err := Init(idxCfg); err != nil {
		t.Fatalf("failed to init indexer: %v", err)
	}
	defer i.Close()

	lessVisitedURL := "https://example.com/visit-facet-less"
	mostVisitedURL := "https://example.com/visit-facet-most"
	docs := []string{
		lessVisitedURL,
		mostVisitedURL,
		mostVisitedURL,
		mostVisitedURL,
	}
	for _, url := range docs {
		if err := Add(&document.Document{
			URL:   url,
			Title: "Visited facet",
			Text:  "Visited facet document text",
		}); err != nil {
			t.Fatalf("Add failed: %v", err)
		}
	}

	res, err := Search(idxCfg, &Query{Text: "Visited facet", Facets: true, FacetsOnly: true})
	if err != nil {
		t.Fatalf("Search failed: %v", err)
	}
	if res.Facets == nil {
		t.Fatal("Facets is nil")
	}
	visits := res.Facets.Terms["visits"].Terms
	counts := make(map[string]int, len(visits))
	labels := make(map[string]string, len(visits))
	for _, bucket := range visits {
		counts[bucket.Term] = bucket.Count
		labels[bucket.Term] = bucket.Label
	}
	if counts["1"] != 1 {
		t.Fatalf("visit bucket 1 = %d, want 1", counts["1"])
	}
	if counts["2..4"] != 1 {
		t.Fatalf("visit bucket 2..4 = %d, want 1", counts["2..4"])
	}
	if labels["2..4"] != "2 to 4" {
		t.Fatalf("visit bucket label 2..4 = %q, want %q", labels["2..4"], "2 to 4")
	}
}
