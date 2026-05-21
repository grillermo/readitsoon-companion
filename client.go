package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

type Article struct {
	ID     int    `json:"id"`
	Title  string `json:"title"`
	Domain string `json:"domain"`
}

type APIClient struct {
	baseURL    string
	email      string
	token      string
	httpClient *http.Client
}

func newAPIClient() *APIClient {
	return &APIClient{
		baseURL: baseURL,
		email:   userEmail,
		token:   authToken,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

func (c *APIClient) doRequest(method, path string) (*http.Response, error) {
	url := fmt.Sprintf("%s%s", c.baseURL, path)
	if strings.Contains(path, "?") {
		url += "&email=" + c.email
	} else {
		url += "?email=" + c.email
	}

	req, err := http.NewRequest(method, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+c.token)
	return c.httpClient.Do(req)
}

func (c *APIClient) fetchPendingArticles() ([]Article, error) {
	resp, err := c.doRequest("GET", "/api/companion/articles")
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("server returned %d", resp.StatusCode)
	}

	var articles []Article
	if err := json.NewDecoder(resp.Body).Decode(&articles); err != nil {
		return nil, err
	}
	return articles, nil
}

func (c *APIClient) fetchMarkdown(articleID int) (string, error) {
	path := fmt.Sprintf("/api/companion/articles/%d/markdown", articleID)
	resp, err := c.doRequest("GET", path)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("server returned %d for article %d", resp.StatusCode, articleID)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	return string(body), nil
}

func (c *APIClient) markDownloaded(articleID int) error {
	path := fmt.Sprintf("/api/companion/articles/%d/downloaded", articleID)
	resp, err := c.doRequest("POST", path)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("server returned %d marking article %d downloaded", resp.StatusCode, articleID)
	}
	return nil
}
