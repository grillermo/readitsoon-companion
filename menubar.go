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

	go poller.start()

	go func() {
		<-mQuit.ClickedCh
		systray.Quit()
	}()
}

func onExit() {}
