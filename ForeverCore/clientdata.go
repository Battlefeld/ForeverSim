package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type clientDataStatus struct {
	Status          string    `json:"status"`
	Message         string    `json:"message"`
	CheckedAt       time.Time `json:"checkedAt,omitempty"`
	AttemptedAt     time.Time `json:"attemptedAt,omitempty"`
	RoutesVersion   string    `json:"routesVersion,omitempty"`
	EngineBuild     string    `json:"engineBuild,omitempty"`
	AvailableBuild  string    `json:"availableBuild,omitempty"`
	EffectiveBuild  string    `json:"effectiveBuild,omitempty"`
	Quests          int       `json:"quests"`
	LocalCacheSHA   string    `json:"localCacheSHA256,omitempty"`
	LocalCacheBuild uint32    `json:"localCacheBuild,omitempty"`
}

func (s *Service) dataStatus() clientDataStatus {
	s.clientMu.Lock()
	defer s.clientMu.Unlock()
	return s.clientStatus
}
func (s *Service) startClientData(ctx context.Context) {
	if s.cfg.Addons == "" || s.cfg.Data == "" {
		return
	}
	s.clientOnce.Do(func() {
		var saved clientDataStatus
		_ = loadJSON(filepath.Join(s.cfg.Data, "ClientData", "status.json"), &saved)
		if saved.Status == "" || (saved.CheckedAt.UTC().Format("2006-01-02") != time.Now().UTC().Format("2006-01-02") && time.Since(saved.AttemptedAt) >= 10*time.Minute) {
			saved.Status = "checking"
			saved.Message = "Daten werden automatisch geprueft"
		}
		s.clientMu.Lock()
		s.clientStatus = saved
		s.clientMu.Unlock()
		go s.watchClientQuests(ctx)
		go func() {
			s.checkClientData(ctx)
			ticker := time.NewTicker(24 * time.Hour)
			defer ticker.Stop()
			for {
				select {
				case <-ctx.Done():
					return
				case <-ticker.C:
					s.checkClientData(ctx)
				}
			}
		}()
	})
}
func (s *Service) checkClientData(ctx context.Context) {
	if !s.clientUpdateMu.TryLock() {
		return
	}
	defer s.clientUpdateMu.Unlock()
	status := s.dataStatus()
	now := time.Now().UTC()
	if status.CheckedAt.Format("2006-01-02") == now.Format("2006-01-02") && (status.Status == "ready" || status.Status == "warning") {
		return
	}
	if !status.AttemptedAt.IsZero() && now.Sub(status.AttemptedAt) < 10*time.Minute {
		return
	}
	s.clientMu.Lock()
	s.clientStatus.Status = "checking"
	s.clientStatus.Message = "Daten werden automatisch geprueft"
	s.clientStatus.AttemptedAt = now
	s.clientMu.Unlock()
	ctx, cancel := context.WithTimeout(ctx, 4*time.Minute)
	defer cancel()
	var issues []string
	if !s.cfg.RoutesNoUpdate {
		v, _, err := updateRoutes(ctx, s.cfg)
		if err != nil {
			issues = append(issues, "Routen-Update: "+err.Error())
		} else {
			status.RoutesVersion = v
		}
	}
	var report struct {
		Products map[string]struct {
			Row struct {
				Version string `json:"VersionsName"`
			} `json:"row"`
		} `json:"products"`
		EffectiveBuild string `json:"effectiveBuild"`
		Coverage       string `json:"hotfixCoverage"`
		CacheSHA       string `json:"exportedCacheSHA256"`
		Extraction     struct {
			Status string `json:"status"`
		} `json:"clientExtraction"`
	}
	raw, err := fetchBounded(ctx, routesAPI+"/repos/Battlefeld/ForeverSim/contents/data-watch/latest/report.json?ref=artifacts", 4<<20)
	if err == nil {
		var file struct {
			Content  string `json:"content"`
			Encoding string `json:"encoding"`
		}
		if err = json.Unmarshal(raw, &file); err == nil {
			if file.Encoding != "base64" {
				err = fmt.Errorf("Datenbericht fehlt")
			} else {
				raw, err = base64.StdEncoding.DecodeString(strings.ReplaceAll(file.Content, "\n", ""))
			}
		}
		if err == nil {
			err = json.Unmarshal(raw, &report)
		}
	}
	if err != nil {
		issues = append(issues, "Hotfix-Pruefung: "+err.Error())
	} else if report.Products["wowf"].Row.Version == "" {
		issues = append(issues, "Hotfix-Bericht ohne Forever-Build")
	}
	var engine struct {
		Build    string `json:"clientBuild"`
		CacheSHA string `json:"hotfixCacheSHA256"`
	}
	_ = loadJSON(filepath.Join(s.cfg.Runtime, "ForeverCore", "engine-data.json"), &engine)
	s.clientMu.Lock()
	defer s.clientMu.Unlock()
	status.Quests = s.clientStatus.Quests
	status.LocalCacheSHA = s.clientStatus.LocalCacheSHA
	status.LocalCacheBuild = s.clientStatus.LocalCacheBuild
	status.AttemptedAt = now
	status.EngineBuild = engine.Build
	status.AvailableBuild = report.Products["wowf"].Row.Version
	status.EffectiveBuild = report.EffectiveBuild
	if len(issues) > 0 {
		status.Status = "error"
		status.Message = "Datenpruefung derzeit nicht moeglich; letzter gueltiger Stand aktiv."
		log.Printf("Datenpruefung: %s", strings.Join(issues, "; "))
	} else {
		status.CheckedAt = now
		status.Status = "ready"
		status.Message = "Routenpaket und Datenbericht automatisch geprueft"
		// A successful metadata check is not proof that the installed engine includes the new hotfixes.
		if report.Extraction.Status != "complete" && report.Coverage != "previous_validated_export" || report.EffectiveBuild == "" || engine.Build != status.AvailableBuild || report.CacheSHA == "" || engine.CacheSHA != report.CacheSHA || status.LocalCacheSHA == "" || engine.CacheSHA != status.LocalCacheSHA {
			status.Status = "warning"
			status.Message = "Hotfix-Pruefung ausstehend; letzter gueltiger Datenstand aktiv."
		}
	}
	s.clientStatus = status
	if err := atomicWrite(filepath.Join(s.cfg.Data, "ClientData", "status.json"), jsonBytes(status)); err != nil {
		log.Printf("Datenstatus speichern: %v", err)
	}
	log.Printf("Automatische Datenpruefung: %s", status.Message)
}
func githubToken() string {
	for _, name := range []string{"FOREVER_GITHUB_TOKEN", "GH_TOKEN", "GITHUB_TOKEN"} {
		if token := os.Getenv(name); token != "" {
			return token
		}
	}
	return ""
}
func githubHost(raw string) bool {
	u, err := url.Parse(raw)
	return err == nil && u.Scheme == "https" && (u.Hostname() == "api.github.com" || u.Hostname() == "github.com")
}
