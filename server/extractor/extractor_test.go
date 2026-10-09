package extractor

import (
	"strings"
	"testing"

	"github.com/asciimoo/hister/server/document"
	"github.com/asciimoo/hister/server/types"
)

func TestReadabilityPreviewSanitizesMetaRefresh(t *testing.T) {
	doc := &document.Document{
		URL: "file:///tmp/index.html",
		HTML: `<!doctype html><html><head><title>Local docs</title>
			<meta http-equiv="refresh" content="0; url=unexpected.html"></head>
			<body><article><h1>Local docs</h1>
				<p>This article has enough readable content for a preview, including
				an image: <img src="x" onerror="alert(1)" alt="unsafe image">.</p>
				<p>The preview must exclude navigation tags from the source head.</p>
			</article></body></html>`,
	}
	resp, state, err := (&readabilityExtractor{}).Preview(doc)
	if err != nil {
		t.Fatal(err)
	}
	if state != types.ExtractorStop {
		t.Fatalf("state = %v, want %v", state, types.ExtractorStop)
	}
	lower := strings.ToLower(resp.Content)
	for _, forbidden := range []string{"http-equiv", "refresh", "unexpected.html", "onerror", "alert(1)"} {
		if strings.Contains(lower, forbidden) {
			t.Errorf("preview contains %q: %s", forbidden, resp.Content)
		}
	}
	if !strings.Contains(resp.Content, "readable content") {
		t.Errorf("preview omitted article text: %s", resp.Content)
	}
}

func TestBasicPreviewEscapesMarkup(t *testing.T) {
	doc := &document.Document{Text: `<p>safe text</p><meta http-equiv="refresh">`}
	resp, state, err := (&basicExtractor{}).Preview(doc)
	if err != nil {
		t.Fatal(err)
	}
	if state != types.ExtractorStop {
		t.Fatalf("state = %v, want %v", state, types.ExtractorStop)
	}
	if strings.Contains(resp.Content, "<p>") || strings.Contains(resp.Content, "<meta") {
		t.Fatalf("preview contains active markup: %s", resp.Content)
	}
	if !strings.Contains(resp.Content, "&lt;p&gt;safe text&lt;/p&gt;") {
		t.Fatalf("preview omitted escaped text: %s", resp.Content)
	}
}
