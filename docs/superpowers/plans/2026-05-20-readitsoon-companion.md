# ReadItSoon Companion Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu bar Go app that polls ReadItSoon for pending articles and saves markdown locally, plus Rails API endpoints and a compile-on-demand download page.

**Architecture:** Two codebases — Rails side adds companion API endpoints + download page; Go side is a systray menu bar app with polling loop. Credentials baked into binary via ldflags at compile time.

**Tech Stack:** Ruby on Rails 8, RSpec, PostgreSQL | Go, getlantern/systray, net/http

---

## Chunk 1: Rails API — Database & Model Layer

### Task 1: Migration — add downloaded_at to articles

**Files:**
- Create: `db/migrate/XXXXXX_add_downloaded_at_to_articles.rb`

**Codebase:** `/Users/grillermo/c/readitsoon`

- [ ] **Step 1: Generate migration**

```bash
cd /Users/grillermo/c/readitsoon
bin/rails generate migration AddDownloadedAtToArticles downloaded_at:datetime
```

- [ ] **Step 2: Run migration**

```bash
bin/rails db:migrate
```

- [ ] **Step 3: Verify schema**

Check `db/schema.rb` has `downloaded_at` on articles table.

- [ ] **Step 4: Commit**

```bash
git add db/
git commit -m "Add downloaded_at column to articles"
```

---

### Task 2: Create companion_tokens table

**Files:**
- Create: `db/migrate/XXXXXX_create_companion_tokens.rb`
- Create: `app/models/companion_token.rb`

**Codebase:** `/Users/grillermo/c/readitsoon`

- [ ] **Step 1: Write model spec**

Create `spec/models/companion_token_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe CompanionToken, type: :model do
  it { is_expected.to belong_to(:email) }
  it { is_expected.to validate_presence_of(:token) }
  it { is_expected.to validate_uniqueness_of(:token) }

  describe ".generate_for" do
    it "creates a token for an email" do
      email = create(:email)
      token = CompanionToken.generate_for(email)
      expect(token.token).to be_present
      expect(token.token.length).to eq(64)
      expect(token.email).to eq(email)
    end

    it "returns existing token if one exists" do
      email = create(:email)
      token1 = CompanionToken.generate_for(email)
      token2 = CompanionToken.generate_for(email)
      expect(token1.id).to eq(token2.id)
    end
  end
end
```

- [ ] **Step 2: Run spec to verify failure**

```bash
bin/rspec spec/models/companion_token_spec.rb
```

Expected: fails (table/model don't exist).

- [ ] **Step 3: Generate migration**

```bash
bin/rails generate migration CreateCompanionTokens email:references token:string:uniq
```

Edit migration to add `null: false` on token column.

- [ ] **Step 4: Run migration**

```bash
bin/rails db:migrate
```

- [ ] **Step 5: Create model**

Create `app/models/companion_token.rb`:

```ruby
class CompanionToken < ApplicationRecord
  belongs_to :email

  validates :token, presence: true, uniqueness: true

  before_validation :set_token, on: :create

  def self.generate_for(email)
    find_or_create_by!(email: email)
  end

  private

  def set_token
    self.token ||= SecureRandom.hex(32)
  end
end
```

- [ ] **Step 6: Run specs — expect pass**

```bash
bin/rspec spec/models/companion_token_spec.rb
```

- [ ] **Step 7: Commit**

```bash
git add db/ app/models/companion_token.rb spec/models/companion_token_spec.rb
git commit -m "Add CompanionToken model with generate_for"
```

---

### Task 3: Add scope to Article for companion

**Files:**
- Modify: `app/models/article.rb`
- Modify: `spec/models/article_spec.rb` (create if not exists)

**Codebase:** `/Users/grillermo/c/readitsoon`

- [ ] **Step 1: Write spec for the scope**

**IMPORTANT:** `spec/models/article_spec.rb` may already exist with other tests. APPEND this describe block inside the existing `RSpec.describe Article` block. Do NOT overwrite existing content. If the file doesn't exist, create it with the full wrapper.

Add to `spec/models/article_spec.rb`:

```ruby
  describe ".pending_download" do
    let(:email) { create(:email) }

    it "returns delivered articles without downloaded_at" do
      pending_article = create(:article, email: email, markdown: "# Hello", sent_status: :delivered, downloaded_at: nil)
      expect(Article.pending_download).to include(pending_article)
    end

    it "excludes already downloaded articles" do
      downloaded = create(:article, email: email, markdown: "# Hello", sent_status: :delivered, downloaded_at: Time.current)
      expect(Article.pending_download).not_to include(downloaded)
    end

    it "excludes articles with nil markdown" do
      no_markdown = create(:article, email: email, markdown: nil, sent_status: :delivered)
      expect(Article.pending_download).not_to include(no_markdown)
    end

    it "excludes non-delivered articles" do
      scheduled = create(:article, email: email, markdown: "# Hello", sent_status: :scheduled)
      expect(Article.pending_download).not_to include(scheduled)
    end
  end
```

- [ ] **Step 2: Run spec to verify failure**

```bash
bin/rspec spec/models/article_spec.rb
```

- [ ] **Step 3: Add scope to Article model**

In `app/models/article.rb`, add:

```ruby
scope :pending_download, -> { where(downloaded_at: nil, sent_status: :delivered).where.not(markdown: nil) }
```

- [ ] **Step 4: Run specs — expect pass**

```bash
bin/rspec spec/models/article_spec.rb
```

- [ ] **Step 5: Commit**

```bash
git add app/models/article.rb spec/models/article_spec.rb
git commit -m "Add Article.pending_download scope"
```

---

## Chunk 2: Rails API — Companion Endpoints

### Task 4: Companion authentication concern

**Files:**
- Create: `app/controllers/concerns/companion_authenticatable.rb`
- Create: `spec/requests/api/companion/authentication_spec.rb`

**Codebase:** `/Users/grillermo/c/readitsoon`

- [ ] **Step 1: Write authentication spec**

```ruby
require "rails_helper"

RSpec.describe "Companion API Authentication", type: :request do
  let(:email) { create(:email) }
  let(:companion_token) { CompanionToken.generate_for(email) }

  describe "missing token" do
    it "returns 401" do
      get "/api/companion/articles", params: { email: email.email }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "invalid token" do
    it "returns 401" do
      get "/api/companion/articles",
        params: { email: email.email },
        headers: { "Authorization" => "Bearer invalid" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "mismatched email" do
    it "returns 401" do
      get "/api/companion/articles",
        params: { email: "wrong@kindle.com" },
        headers: { "Authorization" => "Bearer #{companion_token.token}" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "valid credentials" do
    it "succeeds" do
      get "/api/companion/articles",
        params: { email: email.email },
        headers: { "Authorization" => "Bearer #{companion_token.token}" }
      expect(response).to have_http_status(:ok)
    end
  end
end
```

- [ ] **Step 2: Run spec — expect failure**

```bash
bin/rspec spec/requests/api/companion/authentication_spec.rb
```

- [ ] **Step 3: Create concern**

Create `app/controllers/concerns/companion_authenticatable.rb`:

```ruby
module CompanionAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_companion!
  end

  private

  def authenticate_companion!
    token_string = request.headers["Authorization"]&.delete_prefix("Bearer ")
    companion_token = CompanionToken.find_by(token: token_string)

    if companion_token.nil? || companion_token.email.email != params[:email]
      head :unauthorized
      return
    end

    @current_email = companion_token.email
  end
end
```

- [ ] **Step 4: Create controller and routes (needed for spec to pass)**

Create directory structure first: `mkdir -p app/controllers/api/companion`

Create `app/controllers/api/companion/articles_controller.rb`:

```ruby
module Api
  module Companion
    class ArticlesController < ActionController::API
      include CompanionAuthenticatable

      def index
        articles = @current_email.articles.pending_download
        render json: articles.map { |a|
          { id: a.id, title: a.title, domain: URI.parse(a.url).host rescue "unknown" }
        }
      end
    end
  end
end
```

Add routes to `config/routes.rb`:

```ruby
namespace :api do
  namespace :companion do
    resources :articles, only: [:index] do
      member do
        get :markdown
        post :downloaded
      end
    end
  end
end
```

- [ ] **Step 5: Run spec — expect pass**

```bash
bin/rspec spec/requests/api/companion/authentication_spec.rb
```

- [ ] **Step 6: Commit**

```bash
git add app/controllers/concerns/companion_authenticatable.rb \
  app/controllers/api/companion/articles_controller.rb \
  config/routes.rb \
  spec/requests/api/companion/authentication_spec.rb
git commit -m "Add companion API auth concern and articles index"
```

---

### Task 5: Markdown and downloaded endpoints

**Files:**
- Modify: `app/controllers/api/companion/articles_controller.rb`
- Create: `spec/requests/api/companion/articles_spec.rb`

**Codebase:** `/Users/grillermo/c/readitsoon`

- [ ] **Step 1: Write request specs**

```ruby
require "rails_helper"

RSpec.describe "Companion Articles API", type: :request do
  let(:email) { create(:email) }
  let(:companion_token) { CompanionToken.generate_for(email) }
  let(:headers) { { "Authorization" => "Bearer #{companion_token.token}" } }
  let(:params) { { email: email.email } }

  describe "GET /api/companion/articles" do
    it "returns pending articles with domain" do
      create(:article, email: email, markdown: "# Test", url: "https://blog.example.com/post", sent_status: :delivered)
      get "/api/companion/articles", params: params, headers: headers
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.length).to eq(1)
      expect(json.first["domain"]).to eq("blog.example.com")
    end
  end

  describe "GET /api/companion/articles/:id/markdown" do
    it "returns raw markdown" do
      article = create(:article, email: email, markdown: "# Hello World", sent_status: :delivered)
      get markdown_api_companion_article_path(article), params: params, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/plain")
      expect(response.body).to eq("# Hello World")
    end

    it "rejects article belonging to different email" do
      other_email = create(:email)
      article = create(:article, email: other_email, markdown: "# Nope")
      get markdown_api_companion_article_path(article), params: params, headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/companion/articles/:id/downloaded" do
    it "sets downloaded_at" do
      article = create(:article, email: email, markdown: "# Test", sent_status: :delivered)
      post downloaded_api_companion_article_path(article), params: params, headers: headers
      expect(response).to have_http_status(:ok)
      expect(article.reload.downloaded_at).to be_present
    end

    it "rejects article belonging to different email" do
      other_email = create(:email)
      article = create(:article, email: other_email, markdown: "# Nope")
      post downloaded_api_companion_article_path(article), params: params, headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
```

- [ ] **Step 2: Run specs — expect failure**

```bash
bin/rspec spec/requests/api/companion/articles_spec.rb
```

- [ ] **Step 3: Implement markdown and downloaded actions**

Update `app/controllers/api/companion/articles_controller.rb`:

```ruby
module Api
  module Companion
    class ArticlesController < ActionController::API
      include CompanionAuthenticatable

      def index
        articles = @current_email.articles.pending_download
        render json: articles.map { |a|
          { id: a.id, title: a.title, domain: extract_domain(a.url) }
        }
      end

      def markdown
        article = @current_email.articles.find_by(id: params[:id])
        return head :not_found unless article

        render plain: article.markdown
      end

      def downloaded
        article = @current_email.articles.find_by(id: params[:id])
        return head :not_found unless article

        article.update!(downloaded_at: Time.current)
        head :ok
      end

      private

      def extract_domain(url)
        URI.parse(url).host
      rescue URI::InvalidURIError
        "unknown"
      end
    end
  end
end
```

- [ ] **Step 4: Run specs — expect pass**

```bash
bin/rspec spec/requests/api/companion/articles_spec.rb
```

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/companion/articles_controller.rb \
  spec/requests/api/companion/articles_spec.rb
git commit -m "Add markdown and downloaded companion endpoints"
```

---

## Chunk 3: Rails — Download Companion Page

### Task 6: Download companion controller and view

**Files:**
- Create: `app/controllers/download_companion_controller.rb`
- Create: `app/views/download_companion/show.html.erb`
- Modify: `config/routes.rb`
- Create: `spec/requests/download_companion_spec.rb`

**Codebase:** `/Users/grillermo/c/readitsoon`

- [ ] **Step 1: Write request spec**

```ruby
require "rails_helper"

RSpec.describe "Download Companion", type: :request do
  describe "GET /download-companion" do
    context "with paying user" do
      let(:email) { create(:email, subscription_status: "active") }

      it "renders the download page" do
        get "/download-companion", params: { email: email.email }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Store your reads where they matter to you")
      end
    end

    context "with free user" do
      let(:email) { create(:email, subscription_status: "free") }

      it "rejects access" do
        get "/download-companion", params: { email: email.email }
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "with no subscription status (nil)" do
      let(:email) { create(:email, subscription_status: nil) }

      it "rejects access" do
        get "/download-companion", params: { email: email.email }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /download-companion" do
    let(:email) { create(:email, subscription_status: "active") }

    it "compiles and returns binary" do
      # Stub the compilation
      allow_any_instance_of(DownloadCompanionController).to receive(:compile_companion).and_return("/tmp/readitsoon-companion-test")
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with("/tmp/readitsoon-companion-test").and_return(true)
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with("/tmp/readitsoon-companion-test").and_return("binary-content")

      post "/download-companion", params: { email: email.email }
      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to include("readitsoon-companion")
    end
  end
end
```

- [ ] **Step 2: Run spec — expect failure**

```bash
bin/rspec spec/requests/download_companion_spec.rb
```

- [ ] **Step 3: Add routes**

In `config/routes.rb` add:

```ruby
get "/download-companion", to: "download_companion#show"
post "/download-companion", to: "download_companion#create"
```

- [ ] **Step 4: Create controller**

Create `app/controllers/download_companion_controller.rb`:

```ruby
class DownloadCompanionController < ApplicationController
  before_action :find_email
  before_action :require_paying_user

  def show
  end

  def create
    token = CompanionToken.generate_for(@email)
    binary_path = compile_companion(
      base_url: request.base_url,
      user_email: @email.email,
      auth_token: token.token
    )

    send_file binary_path,
      filename: "readitsoon-companion",
      type: "application/octet-stream",
      disposition: "attachment"
  ensure
    # Clean up temp files after streaming
    FileUtils.rm_rf(File.dirname(binary_path)) if binary_path
  end

  private

  def find_email
    @email = Email.find_by(email: params[:email])
    head :not_found unless @email
  end

  def require_paying_user
    unless @email&.subscription_status.in?(%w[active trialing])
      head :forbidden
    end
  end

  def compile_companion(base_url:, user_email:, auth_token:)
    companion_src = Rails.root.join("..", "readitsoon-companion").to_s
    output_dir = Dir.mktmpdir
    arm64_path = File.join(output_dir, "companion-arm64")
    amd64_path = File.join(output_dir, "companion-amd64")
    universal_path = File.join(output_dir, "readitsoon-companion")

    ldflags = "-X main.baseURL=#{base_url} -X main.userEmail=#{user_email} -X main.authToken=#{auth_token}"

    system(
      { "CGO_ENABLED" => "1", "GOOS" => "darwin", "GOARCH" => "arm64" },
      "go", "build", "-ldflags", ldflags, "-o", arm64_path, companion_src,
      exception: true
    )
    system(
      { "CGO_ENABLED" => "1", "GOOS" => "darwin", "GOARCH" => "amd64" },
      "go", "build", "-ldflags", ldflags, "-o", amd64_path, companion_src,
      exception: true
    )
    system("lipo", "-create", "-output", universal_path, arm64_path, amd64_path, exception: true)

    universal_path
  end
end
```

- [ ] **Step 5: Create view**

Create `app/views/download_companion/show.html.erb`:

```erb
<div class="companion-download">
  <h1>ReadItSoon Companion</h1>

  <div class="marketing">
    <p><strong>Store your reads where they matter to you</strong></p>
    <p>Save them in your "second brain"</p>
    <p>Allow your favorite agent to read them</p>
    <p>Annotate them</p>
  </div>

  <div class="explanation">
    <h2>What it does</h2>
    <p>A lightweight macOS menu bar app that runs in the background.
       Every minute it checks for new articles you've sent through ReadItSoon
       and saves the markdown files to a folder you choose on first run.</p>
  </div>

  <div class="requirements">
    <h2>Requirements</h2>
    <ul>
      <li>macOS (Apple Silicon + Intel supported)</li>
      <li>On first run, you'll choose where to save files</li>
      <li>Optionally installs as a background service (LaunchAgent)</li>
    </ul>
  </div>

  <%= button_to "Download Companion", "/download-companion",
    params: { email: params[:email] },
    class: "download-button" %>
</div>
```

- [ ] **Step 6: Run specs — expect pass**

```bash
bin/rspec spec/requests/download_companion_spec.rb
```

- [ ] **Step 7: Commit**

```bash
git add app/controllers/download_companion_controller.rb \
  app/views/download_companion/show.html.erb \
  config/routes.rb \
  spec/requests/download_companion_spec.rb
git commit -m "Add download companion page with compile-on-demand"
```

---

## Chunk 4: Go Companion — Project Setup & Polling

### Task 7: Initialize Go module and project structure

**Files:**
- Create: `go.mod`
- Create: `main.go`
- Create: `config.go`

**Codebase:** `/Users/grillermo/c/readitsoon-companion`

- [ ] **Step 1: Initialize Go module**

```bash
cd /Users/grillermo/c/readitsoon-companion
go mod init github.com/grillermo/readitsoon-companion
```

- [ ] **Step 2: Create main.go with compile-time vars and entry point**

```go
package main

import (
	"fmt"
	"os"
)

var (
	baseURL   string
	userEmail string
	authToken string
)

func main() {
	if baseURL == "" || userEmail == "" || authToken == "" {
		fmt.Fprintln(os.Stderr, "Error: this binary was not compiled with required credentials.")
		fmt.Fprintln(os.Stderr, "Download from your ReadItSoon account.")
		os.Exit(1)
	}

	cfg, err := loadOrCreateConfig()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Config error: %v\n", err)
		os.Exit(1)
	}

	if cfg.SavePath == "" {
		cfg.SavePath, err = promptSavePath()
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
		if err := cfg.save(); err != nil {
			fmt.Fprintf(os.Stderr, "Error saving config: %v\n", err)
			os.Exit(1)
		}
	}

	if !cfg.ServiceInstalled {
		if promptInstallService() {
			if err := installLaunchAgent(); err != nil {
				fmt.Fprintf(os.Stderr, "Warning: could not install service: %v\n", err)
			} else {
				cfg.ServiceInstalled = true
				cfg.save()
			}
		}
	}

	runMenuBar(cfg)
}
```

- [ ] **Step 3: Create config.go**

```go
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type Config struct {
	SavePath         string `json:"save_path"`
	ServiceInstalled bool   `json:"service_installed"`
	path             string
}

func configPath() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".readitsoon-companion.json")
}

func loadOrCreateConfig() (*Config, error) {
	path := configPath()
	cfg := &Config{path: path}

	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return cfg, nil
		}
		return nil, err
	}

	if err := json.Unmarshal(data, cfg); err != nil {
		return nil, err
	}
	cfg.path = path
	return cfg, nil
}

func (c *Config) save() error {
	data, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(c.path, data, 0644)
}

func promptSavePath() (string, error) {
	reader := bufio.NewReader(os.Stdin)
	fmt.Print("Where should ReadItSoon save markdown files? (absolute path): ")
	path, err := reader.ReadString('\n')
	if err != nil {
		return "", err
	}
	path = strings.TrimSpace(path)

	if !filepath.IsAbs(path) {
		return "", fmt.Errorf("path must be absolute: %s", path)
	}

	if err := os.MkdirAll(path, 0755); err != nil {
		return "", fmt.Errorf("cannot create directory: %w", err)
	}

	return path, nil
}

func promptInstallService() bool {
	reader := bufio.NewReader(os.Stdin)
	fmt.Print("Install as background service (runs on login)? [y/n]: ")
	answer, _ := reader.ReadString('\n')
	return strings.TrimSpace(strings.ToLower(answer)) == "y"
}
```

- [ ] **Step 4: Verify it compiles**

```bash
go build -ldflags "-X main.baseURL=http://test -X main.userEmail=test@kindle.com -X main.authToken=abc" -o /tmp/companion-test .
```

(Will fail on `runMenuBar` and `installLaunchAgent` — that's expected, we'll add those next.)

- [ ] **Step 5: Commit**

```bash
git add go.mod main.go config.go
git commit -m "Init Go project with config and first-run prompts"
```

---

### Task 8: LaunchAgent installation

**Files:**
- Create: `service.go`

**Codebase:** `/Users/grillermo/c/readitsoon-companion`

- [ ] **Step 1: Create service.go**

```go
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"text/template"
)

const plistTemplate = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.readitsoon.companion</string>
    <key>ProgramArguments</key>
    <array>
        <string>{{.BinaryPath}}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>`

func installLaunchAgent() error {
	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}

	launchAgentsDir := filepath.Join(home, "Library", "LaunchAgents")
	if err := os.MkdirAll(launchAgentsDir, 0755); err != nil {
		return err
	}

	plistPath := filepath.Join(launchAgentsDir, "com.readitsoon.companion.plist")

	binaryPath, err := os.Executable()
	if err != nil {
		return err
	}

	tmpl, err := template.New("plist").Parse(plistTemplate)
	if err != nil {
		return err
	}

	f, err := os.Create(plistPath)
	if err != nil {
		return err
	}
	defer f.Close()

	if err := tmpl.Execute(f, struct{ BinaryPath string }{binaryPath}); err != nil {
		return err
	}

	fmt.Printf("Service installed at %s\n", plistPath)
	fmt.Println("It will start automatically on next login.")
	return nil
}
```

- [ ] **Step 2: Commit**

```bash
git add service.go
git commit -m "Add LaunchAgent installation"
```

---

### Task 9: API client and polling

**Files:**
- Create: `client.go`
- Create: `poller.go`

**Codebase:** `/Users/grillermo/c/readitsoon-companion`

- [ ] **Step 1: Create client.go**

```go
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
	baseURL   string
	email     string
	token     string
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
```

- [ ] **Step 2: Create poller.go**

```go
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
```

- [ ] **Step 3: Verify compilation**

```bash
go build -ldflags "-X main.baseURL=http://test -X main.userEmail=test@kindle.com -X main.authToken=abc" -o /tmp/companion-test .
```

(Still missing `runMenuBar` — next task.)

- [ ] **Step 4: Commit**

```bash
git add client.go poller.go
git commit -m "Add API client and polling loop with concurrent downloads"
```

---

## Chunk 5: Go Companion — Menu Bar & Icon

### Task 10: Menu bar with systray

**Files:**
- Create: `menubar.go`
- Create: `icons.go`

**Codebase:** `/Users/grillermo/c/readitsoon-companion`

- [ ] **Step 1: Add systray dependency**

```bash
go get github.com/getlantern/systray
```

- [ ] **Step 2: Create icons.go**

Pre-process the icon: convert the SVG to all-white PNG at 22x22 and 44x44, base64 encode, embed as byte slices. For now, use a placeholder white square — replace with actual icon later.

```go
package main

// Icon assets embedded as byte slices.
// Generated from readitsoon icon.svg (all-white version).
// Replace these with actual PNG bytes from icon conversion.

// iconDefault is the white ReadItSoon logo, 22x22 PNG template image
var iconDefault []byte

// iconDownloading is the clock emoji state
var iconDownloading []byte

// iconDone is the checkmark emoji state
var iconDone []byte

func init() {
	// Placeholder: 1x1 white PNG (will be replaced with actual icons)
	// This allows compilation while icons are being prepared
	placeholder := []byte{
		0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
		0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
		0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
		0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
		0x00, 0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC, 0x33, 0x00, 0x00, 0x00,
		0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
	}
	iconDefault = placeholder
	iconDownloading = placeholder
	iconDone = placeholder
}
```

- [ ] **Step 3: Create menubar.go**

```go
package main

import (
	"fmt"
	"time"

	"github.com/getlantern/systray"
)

func runMenuBar(cfg *Config) {
	systray.Run(func() { onReady(cfg) }, onExit)
}

func onReady(cfg *Config) {
	systray.SetIcon(iconDefault)
	systray.SetTooltip("ReadItSoon Companion")

	mStatus := systray.AddMenuItem(
		fmt.Sprintf("Monitoring for files sent to %s", userEmail),
		"",
	)
	mStatus.Disable()

	systray.AddSeparator()
	mQuit := systray.AddMenuItem("Quit", "Quit the companion")

	poller := newPoller(cfg)
	poller.onStart = func() {
		systray.SetIcon(iconDownloading)
	}
	poller.onDone = func() {
		systray.SetIcon(iconDone)
		time.AfterFunc(5*time.Second, func() {
			systray.SetIcon(iconDefault)
		})
	}

	go poller.start()

	go func() {
		<-mQuit.ClickedCh
		systray.Quit()
	}()
}

func onExit() {
	// Cleanup if needed
}
```

- [ ] **Step 4: Build and verify**

```bash
go mod tidy
go build -ldflags "-X main.baseURL=http://localhost:3000 -X main.userEmail=test@kindle.com -X main.authToken=abc123" -o /tmp/companion-test .
```

- [ ] **Step 5: Commit**

```bash
git add menubar.go icons.go go.mod go.sum
git commit -m "Add macOS menu bar with systray and icon states"
```

---

### Task 11: Convert icon to white template images

**Files:**
- Create: `script/generate-icons.sh`
- Modify: `icons.go`

**Codebase:** `/Users/grillermo/c/readitsoon-companion`

- [ ] **Step 1: Create icon generation script**

This script converts the SVG to all-white and renders PNGs. Requires `rsvg-convert` (from librsvg) and `sed`.

Create `script/generate-icons.sh`:

```bash
#!/bin/bash
set -e

ICON_SRC="/Users/grillermo/c/readitsoon/public/icon.svg"
OUT_DIR="$(dirname "$0")/../assets"
mkdir -p "$OUT_DIR"

# Make all fills white
sed 's/fill="#[a-fA-F0-9]\{6\}"/fill="#FFFFFF"/g' "$ICON_SRC" > "$OUT_DIR/icon-white.svg"

# Render at menu bar sizes
rsvg-convert -w 22 -h 22 "$OUT_DIR/icon-white.svg" > "$OUT_DIR/icon-22.png"
rsvg-convert -w 44 -h 44 "$OUT_DIR/icon-white.svg" > "$OUT_DIR/icon-44.png"

echo "Icons generated in $OUT_DIR"
echo "icons.go uses //go:embed assets/icon-22.png"
```

- [ ] **Step 2: Run the script**

```bash
chmod +x script/generate-icons.sh
bash script/generate-icons.sh
```

If `rsvg-convert` is not available, install with `brew install librsvg`.

- [ ] **Step 3: Replace icons.go with embed version**

**DELETE** the placeholder `icons.go` from Task 10 entirely. Replace with:

```go
package main

import _ "embed"

//go:embed assets/icon-22.png
var iconDefault []byte

// Same icon for all states — tooltip changes to show status
var iconDownloading []byte
var iconDone []byte

func init() {
	iconDownloading = iconDefault
	iconDone = iconDefault
}
```

Also **DELETE** `icons_generated.go` if it was created by the script (the embed directive is now in icons.go directly).

Update `menubar.go` to change tooltip for states:

```go
poller.onStart = func() {
    systray.SetIcon(iconDefault)
    systray.SetTooltip("🕐 Downloading...")
}
poller.onDone = func() {
    systray.SetIcon(iconDefault)
    systray.SetTooltip("✅ Downloads complete")
    time.AfterFunc(5*time.Second, func() {
        systray.SetTooltip("ReadItSoon Companion")
    })
}
```

- [ ] **Step 4: Build and verify**

```bash
go build -ldflags "-X main.baseURL=http://localhost:3000 -X main.userEmail=test@kindle.com -X main.authToken=abc123" -o /tmp/companion-test .
```

- [ ] **Step 5: Commit**

```bash
git add script/generate-icons.sh assets/ icons.go menubar.go
git commit -m "Add white icon generation and embed for menu bar"
```

---

## Chunk 6: Rate Limiting & Integration

### Task 12: Add rate limiting to companion API endpoints

**Files:**
- Modify: `config/initializers/rack_attack.rb` (or create if not exists)
- Create: `spec/requests/api/companion/rate_limiting_spec.rb`

**Codebase:** `/Users/grillermo/c/readitsoon`

The spec requires rate limiting: server rejects polls more frequent than 1 per 30 seconds per token.

- [ ] **Step 1: Write rate limiting spec**

```ruby
require "rails_helper"

RSpec.describe "Companion API Rate Limiting", type: :request do
  let(:email) { create(:email) }
  let(:companion_token) { CompanionToken.generate_for(email) }
  let(:headers) { { "Authorization" => "Bearer #{companion_token.token}" } }

  it "rate limits companion API requests per token" do
    # Rack::Attack cache is reset before each test (see rails_helper.rb)
    3.times do
      get "/api/companion/articles", params: { email: email.email }, headers: headers
    end
    expect(response).to have_http_status(:too_many_requests)
  end
end
```

- [ ] **Step 2: Run spec — expect failure**

```bash
bin/rspec spec/requests/api/companion/rate_limiting_spec.rb
```

- [ ] **Step 3: Add Rack::Attack throttle rule**

Check if `config/initializers/rack_attack.rb` exists. Add companion throttle:

```ruby
Rack::Attack.throttle("companion_api/token", limit: 2, period: 30.seconds) do |req|
  if req.path.start_with?("/api/companion")
    req.get_header("HTTP_AUTHORIZATION")&.delete_prefix("Bearer ")
  end
end
```

- [ ] **Step 4: Run spec — expect pass**

```bash
bin/rspec spec/requests/api/companion/rate_limiting_spec.rb
```

- [ ] **Step 5: Commit**

```bash
git add config/initializers/rack_attack.rb spec/requests/api/companion/rate_limiting_spec.rb
git commit -m "Add rate limiting for companion API (2 req/30s per token)"
```

---

### Task 13: Final Go build verification

**Codebase:** `/Users/grillermo/c/readitsoon-companion`

- [ ] **Step 1: Full compilation**

```bash
cd /Users/grillermo/c/readitsoon-companion
go mod tidy
go build -ldflags "-X main.baseURL=http://localhost:3000 -X main.userEmail=test@kindle.com -X main.authToken=abc123" -o /tmp/readitsoon-companion .
```

- [ ] **Step 2: Fix any compilation errors and commit**

- [ ] **Step 3: Test first-run flow**

```bash
/tmp/readitsoon-companion
```

Should prompt for save path and service installation.

---

### Task 14: Run full Rails test suite

**Codebase:** `/Users/grillermo/c/readitsoon`

- [ ] **Step 1: Run all specs**

```bash
cd /Users/grillermo/c/readitsoon
bin/rspec
```

- [ ] **Step 2: Fix any failures**

Ensure no regressions from new routes/migrations.

- [ ] **Step 3: Manual integration test**

1. Start Rails server: `bin/rails s`
2. Create a test email with subscription: `Email.create(email: "test@kindle.com", subscription_status: "active")`
3. Create companion token: `CompanionToken.generate_for(Email.last)`
4. Create article: `Article.create(email: Email.last, url: "https://example.com/test", title: "Test", markdown: "# Hello", sent_status: :delivered)`
5. Curl the API:
   ```bash
   curl -H "Authorization: Bearer TOKEN" "http://localhost:3000/api/companion/articles?email=test@kindle.com"
   ```
6. Run companion binary against local server

- [ ] **Step 4: Final commit if any fixes**

```bash
git add .
git commit -m "Integration fixes from end-to-end testing"
```
