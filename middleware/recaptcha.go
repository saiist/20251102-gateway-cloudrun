package middleware

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
)

type RecaptchaResponse struct {
	Success     bool     `json:"success"`
	Score       float64  `json:"score"`
	Action      string   `json:"action"`
	ChallengeTS string   `json:"challenge_ts"`
	Hostname    string   `json:"hostname"`
	ErrorCodes  []string `json:"error-codes"`
}

func RecaptchaVerify(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// OPTIONSリクエストはスキップ
		if r.Method == "OPTIONS" {
			next.ServeHTTP(w, r)
			return
		}

		// reCAPTCHAトークンの取得
		token := r.Header.Get("x-recaptcha-token")

		// トークンが空の場合はスキップ（開発環境など）
		if token == "" {
			log.Println("Warning: No reCAPTCHA token provided")
			next.ServeHTTP(w, r)
			return
		}

		// シークレットキーの取得
		secretKey := os.Getenv("RECAPTCHA_SECRET_KEY")
		if secretKey == "" {
			log.Println("Warning: RECAPTCHA_SECRET_KEY not set")
			next.ServeHTTP(w, r)
			return
		}

		// reCAPTCHA検証
		if !verifyRecaptcha(token, secretKey) {
			http.Error(w, `{"error":"reCAPTCHA verification failed"}`, http.StatusForbidden)
			return
		}

		next.ServeHTTP(w, r)
	})
}

func verifyRecaptcha(token, secretKey string) bool {
	// Google reCAPTCHA API endpoint
	verifyURL := "https://www.google.com/recaptcha/api/siteverify"

	// パラメータの準備
	data := url.Values{}
	data.Set("secret", secretKey)
	data.Set("response", token)

	// POSTリクエスト
	resp, err := http.PostForm(verifyURL, data)
	if err != nil {
		log.Printf("reCAPTCHA verification error: %v", err)
		return false
	}
	defer resp.Body.Close()

	// レスポンスの読み取り
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Printf("reCAPTCHA response read error: %v", err)
		return false
	}

	// JSONパース
	var result RecaptchaResponse
	if err := json.Unmarshal(body, &result); err != nil {
		log.Printf("reCAPTCHA response parse error: %v", err)
		return false
	}

	// 検証結果のログ
	log.Printf("reCAPTCHA: success=%v, score=%.2f, action=%s", result.Success, result.Score, result.Action)

	// 検証失敗の場合
	if !result.Success {
		log.Printf("reCAPTCHA verification failed: %v", result.ErrorCodes)
		return false
	}

	// スコアチェック（0.5以上を人間と判定）
	if result.Score < 0.5 {
		log.Printf("reCAPTCHA score too low: %.2f", result.Score)
		return false
	}

	// アクションチェック
	if result.Action != "api_call" {
		log.Printf("reCAPTCHA action mismatch: %s", result.Action)
		return false
	}

	log.Printf("reCAPTCHA verification successful: score=%.2f", result.Score)
	return true
}

// RecaptchaVerifyWithThreshold allows custom score threshold
func RecaptchaVerifyWithThreshold(threshold float64) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Method == "OPTIONS" {
				next.ServeHTTP(w, r)
				return
			}

			token := r.Header.Get("x-recaptcha-token")
			if token == "" {
				log.Println("Warning: No reCAPTCHA token provided")
				next.ServeHTTP(w, r)
				return
			}

			secretKey := os.Getenv("RECAPTCHA_SECRET_KEY")
			if secretKey == "" {
				log.Println("Warning: RECAPTCHA_SECRET_KEY not set")
				next.ServeHTTP(w, r)
				return
			}

			if !verifyRecaptchaWithThreshold(token, secretKey, threshold) {
				http.Error(w, fmt.Sprintf(`{"error":"reCAPTCHA verification failed, score below %.2f"}`, threshold), http.StatusForbidden)
				return
			}

			next.ServeHTTP(w, r)
		})
	}
}

func verifyRecaptchaWithThreshold(token, secretKey string, threshold float64) bool {
	verifyURL := "https://www.google.com/recaptcha/api/siteverify"

	data := url.Values{}
	data.Set("secret", secretKey)
	data.Set("response", token)

	resp, err := http.PostForm(verifyURL, data)
	if err != nil {
		log.Printf("reCAPTCHA verification error: %v", err)
		return false
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Printf("reCAPTCHA response read error: %v", err)
		return false
	}

	var result RecaptchaResponse
	if err := json.Unmarshal(body, &result); err != nil {
		log.Printf("reCAPTCHA response parse error: %v", err)
		return false
	}

	log.Printf("reCAPTCHA: success=%v, score=%.2f, action=%s", result.Success, result.Score, result.Action)

	if !result.Success {
		log.Printf("reCAPTCHA verification failed: %v", result.ErrorCodes)
		return false
	}

	if result.Score < threshold {
		log.Printf("reCAPTCHA score too low: %.2f (threshold: %.2f)", result.Score, threshold)
		return false
	}

	if result.Action != "api_call" {
		log.Printf("reCAPTCHA action mismatch: %s", result.Action)
		return false
	}

	log.Printf("reCAPTCHA verification successful: score=%.2f", result.Score)
	return true
}
