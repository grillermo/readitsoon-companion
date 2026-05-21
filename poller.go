package main

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"
)

type Poller struct {
	client   *APIClient
	savePath string
	onStart  func()
	onDone   func()
}

func newPoller(cfg *Config) *Poller {
	return &Poller{
		client:   newAPIClient(),
		savePath: cfg.SavePath,
	}
}

func (p *Poller) start() {
	ticker := time.NewTicker(60 * time.Second)
	defer ticker.Stop()

	// Poll immediately on start
	p.poll()

	for range ticker.C {
		p.poll()
	}
}

func (p *Poller) poll() {
	articles, err := p.client.fetchPendingArticles()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Poll error: %v\n", err)
		return
	}

	if len(articles) == 0 {
		return
	}

	if p.onStart != nil {
		p.onStart()
	}

	sem := make(chan struct{}, 3)
	var wg sync.WaitGroup

	for _, article := range articles {
		wg.Add(1)
		sem <- struct{}{}
		go func(a Article) {
			defer wg.Done()
			defer func() { <-sem }()
			p.downloadArticle(a)
		}(article)
	}

	wg.Wait()

	if p.onDone != nil {
		p.onDone()
	}
}

func (p *Poller) downloadArticle(article Article) {
	markdown, err := p.client.fetchMarkdown(article.ID)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Download error (article %d): %v\n", article.ID, err)
		return
	}

	domainDir := filepath.Join(p.savePath, article.Domain)
	if err := os.MkdirAll(domainDir, 0755); err != nil {
		fmt.Fprintf(os.Stderr, "Dir error: %v\n", err)
		return
	}

	filename := sanitizeTitle(article.Title) + ".md"
	fullPath := resolveCollision(filepath.Join(domainDir, filename))

	if err := os.WriteFile(fullPath, []byte(markdown), 0644); err != nil {
		fmt.Fprintf(os.Stderr, "Write error: %v\n", err)
		return
	}

	if err := p.client.markDownloaded(article.ID); err != nil {
		fmt.Fprintf(os.Stderr, "Mark downloaded error (article %d): %v\n", article.ID, err)
	}
}

var nonAlphanumeric = regexp.MustCompile(`[^a-z0-9-]`)

func sanitizeTitle(title string) string {
	s := strings.ToLower(title)
	s = strings.ReplaceAll(s, " ", "-")
	s = nonAlphanumeric.ReplaceAllString(s, "")
	if s == "" {
		s = "untitled"
	}
	return s
}

func resolveCollision(path string) string {
	if _, err := os.Stat(path); os.IsNotExist(err) {
		return path
	}

	ext := filepath.Ext(path)
	base := strings.TrimSuffix(path, ext)

	for i := 2; i < 1000; i++ {
		candidate := fmt.Sprintf("%s-%d%s", base, i, ext)
		if _, err := os.Stat(candidate); os.IsNotExist(err) {
			return candidate
		}
	}
	return path
}
