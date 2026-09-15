package store

import (
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/t9-messenger/t9/server/internal/crypto"

	_ "modernc.org/sqlite"
)

func envTruthy(k string) bool {
	switch os.Getenv(k) {
	case "1", "true", "TRUE", "yes", "YES", "on", "ON":
		return true
	default:
		return false
	}
}

var (
	ErrNotFound       = errors.New("not found")
	ErrConflict       = errors.New("conflict")
	ErrInactive       = errors.New("account not active")
	ErrDeviceBound     = errors.New("device already bound")
	ErrPendingExpired = errors.New("pending login expired")
	ErrDenied         = errors.New("denied")
)

type Store struct {
	db       *sql.DB
	mu       sync.Mutex
	dataDir  string
	sealed   string // path to encrypted file on disk
	workPath string // plaintext working sqlite (process-local)
	master   []byte
	colKey   []byte
	fp       string
}

type Account struct {
	ID              string
	Username        string
	PasswordHash    string
	TOTPEnc         []byte
	Active          bool
	Pubkey          string
	CreatedAt       time.Time
	EnrollExpiresAt time.Time // zero if active / not applicable
}

type PendingLogin struct {
	ID           string
	AccountID    string
	DeviceID     string
	Assertion    string
	Status       string // pending|approved|denied
	DeviceToken  string // plaintext only while approved & not yet polled empty; we store hash + return once
	TokenOnce    string // one-shot plaintext token for poller
	ExpiresAt    time.Time
	CreatedAt    time.Time
}

type DeviceSession struct {
	ID        string
	AccountID string
	DeviceID  string
	TokenHash string
	PushToken string
	CreatedAt time.Time
}

type Message struct {
	ID             string
	RecipientAccID string
	SenderUsername string
	Ciphertext     []byte
	CreatedAt      time.Time
	ExpiresAt      time.Time
}

// Open decrypts sealed DB (or creates new), opens SQLite, migrates.
func Open(dataDir string, master []byte) (*Store, error) {
	if err := os.MkdirAll(dataDir, 0o700); err != nil {
		return nil, err
	}
	sealed := filepath.Join(dataDir, "t9.db.sealed")
	keyFPPath := filepath.Join(dataDir, "t9.db.keyfp")
	workPath := filepath.Join(dataDir, ".t9.work.db")
	_ = os.Remove(workPath)

	sum := sha256.Sum256(master)
	masterFP := fmt.Sprintf("%x", sum[:8])

	if envTruthy("T9_RESET_DB") {
		_ = os.Remove(sealed)
		_ = os.Remove(keyFPPath)
	}

	if _, err := os.Stat(sealed); err == nil {
		raw, err := os.ReadFile(sealed)
		if err != nil {
			return nil, err
		}
		storedFP, _ := os.ReadFile(keyFPPath)
		plain, err := crypto.OpenFile(master, raw)
		if err != nil {
			hint := "T9_DB_KEY does not match the sealed database (or the file is corrupt). " +
				"Restore the original key, or recreate data with T9_RESET_DB=1 once " +
				"(destroys mailbox data), or remove the Docker volume."
			if len(storedFP) > 0 && string(storedFP) != masterFP {
				hint = fmt.Sprintf("T9_DB_KEY fingerprint mismatch (stored=%s current=%s). %s",
					string(storedFP), masterFP, hint)
			}
			return nil, fmt.Errorf("%s: %w", hint, err)
		}
		if err := os.WriteFile(workPath, plain, 0o600); err != nil {
			return nil, err
		}
		_ = os.WriteFile(keyFPPath, []byte(masterFP), 0o600)
	}

	dsn := fmt.Sprintf("file:%s?_pragma=busy_timeout(5000)&_pragma=foreign_keys(1)&_pragma=journal_mode(DELETE)", workPath)
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)

	s := &Store{
		db:       db,
		dataDir:  dataDir,
		sealed:   sealed,
		workPath: workPath,
		master:   append([]byte(nil), master...),
		colKey:   crypto.DeriveAESKey(master, "t9-column-v1"),
	}
	if err := s.migrate(); err != nil {
		_ = db.Close()
		return nil, err
	}
	if err := s.ensureServerIdentity(); err != nil {
		_ = db.Close()
		return nil, err
	}
	if err := s.SealNow(); err != nil {
		_ = db.Close()
		return nil, err
	}
	_ = os.WriteFile(keyFPPath, []byte(masterFP), 0o600)
	return s, nil
}

func (s *Store) Fingerprint() string { return s.fp }

func (s *Store) migrate() error {
	_, err := s.db.Exec(`
CREATE TABLE IF NOT EXISTS meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS accounts (
  id TEXT PRIMARY KEY,
  username TEXT NOT NULL UNIQUE COLLATE NOCASE,
  password_hash TEXT NOT NULL,
  totp_enc BLOB NOT NULL,
  active INTEGER NOT NULL DEFAULT 0,
  pubkey TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  enroll_expires_at TEXT NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS pending_device_logins (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id),
  device_id TEXT NOT NULL,
  assertion TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL,
  token_once TEXT NOT NULL DEFAULT '',
  expires_at TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS device_sessions (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL UNIQUE REFERENCES accounts(id),
  device_id TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  push_token TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  recipient_account_id TEXT NOT NULL REFERENCES accounts(id),
  sender_username TEXT NOT NULL,
  ciphertext BLOB NOT NULL,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_messages_recipient ON messages(recipient_account_id);
CREATE INDEX IF NOT EXISTS idx_messages_expires ON messages(expires_at);
CREATE INDEX IF NOT EXISTS idx_pending_expires ON pending_device_logins(expires_at);
`)
	if err != nil {
		return err
	}
	_, _ = s.db.Exec(`ALTER TABLE accounts ADD COLUMN enroll_expires_at TEXT NOT NULL DEFAULT ''`)
	_, _ = s.db.Exec(`ALTER TABLE device_sessions ADD COLUMN push_token TEXT NOT NULL DEFAULT ''`)
	return nil
}

func (s *Store) ensureServerIdentity() error {
	var v string
	err := s.db.QueryRow(`SELECT value FROM meta WHERE key = 'server_id'`).Scan(&v)
	if errors.Is(err, sql.ErrNoRows) {
		id, err := crypto.RandomToken(32)
		if err != nil {
			return err
		}
		if _, err := s.db.Exec(`INSERT INTO meta(key,value) VALUES('server_id',?)`, id); err != nil {
			return err
		}
		v = id
	} else if err != nil {
		return err
	}
	s.fp = crypto.FingerprintHex([]byte(v))
	return nil
}

// SealNow flushes SQLite and writes encrypted file; working file remains for process use.
func (s *Store) SealNow() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, err := s.db.Exec(`PRAGMA wal_checkpoint(TRUNCATE)`); err != nil {
		// ignore if not wal
		_, _ = s.db.Exec(`PRAGMA wal_checkpoint(FULL)`)
	}
	plain, err := os.ReadFile(s.workPath)
	if err != nil {
		return err
	}
	// also capture -wal/-shm if present by forcing checkpoint then read main
	sealed, err := crypto.SealFile(s.master, plain)
	if err != nil {
		return err
	}
	tmp := s.sealed + ".tmp"
	if err := os.WriteFile(tmp, sealed, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, s.sealed)
}

func (s *Store) Close() error {
	_ = s.SealNow()
	err := s.db.Close()
	_ = os.Remove(s.workPath)
	_ = os.Remove(s.workPath + "-wal")
	_ = os.Remove(s.workPath + "-shm")
	return err
}

func (s *Store) encryptCol(plain string) ([]byte, error) {
	return crypto.Seal(s.colKey, []byte(plain), []byte("totp"))
}

func (s *Store) decryptCol(sealed []byte) (string, error) {
	b, err := crypto.Open(s.colKey, sealed, []byte("totp"))
	if err != nil {
		return "", err
	}
	return string(b), nil
}

func nowUTC() time.Time { return time.Now().UTC() }

func fmtTime(t time.Time) string { return t.UTC().Format(time.RFC3339Nano) }

func parseTime(s string) (time.Time, error) {
	return time.Parse(time.RFC3339Nano, s)
}

// CreateAccountInactive stores usr/pw + encrypted TOTP; active=false until confirm.
// An unfinished enrollment for the same username is deleted so the handle is free.
func (s *Store) CreateAccountInactive(username, passwordHash, totpSecret string, enrollTTL time.Duration) (*Account, error) {
	if err := s.deleteInactiveUsername(username); err != nil {
		return nil, err
	}
	if existing, err := s.GetAccountByUsername(username); err == nil && existing.Active {
		return nil, ErrConflict
	} else if err != nil && !errors.Is(err, ErrNotFound) {
		return nil, err
	}
	enc, err := s.encryptCol(totpSecret)
	if err != nil {
		return nil, err
	}
	id := uuid.NewString()
	t := nowUTC()
	exp := t.Add(enrollTTL)
	_, err = s.db.Exec(
		`INSERT INTO accounts(id,username,password_hash,totp_enc,active,pubkey,created_at,enroll_expires_at) VALUES(?,?,?,?,0,'',?,?)`,
		id, username, passwordHash, enc, fmtTime(t), fmtTime(exp),
	)
	if err != nil {
		if isUnique(err) {
			return nil, ErrConflict
		}
		return nil, err
	}
	_ = s.SealNow()
	return &Account{ID: id, Username: username, PasswordHash: passwordHash, TOTPEnc: enc, Active: false, CreatedAt: t, EnrollExpiresAt: exp}, nil
}

func (s *Store) deleteInactiveUsername(username string) error {
	acc, err := s.GetAccountByUsername(username)
	if err != nil {
		if errors.Is(err, ErrNotFound) {
			return nil
		}
		return err
	}
	if acc.Active {
		return nil
	}
	return s.deleteAccountRow(acc.ID)
}

func (s *Store) deleteAccountRow(id string) error {
	_, _ = s.db.Exec(`DELETE FROM messages WHERE recipient_account_id=?`, id)
	_, _ = s.db.Exec(`DELETE FROM pending_device_logins WHERE account_id=?`, id)
	_, _ = s.db.Exec(`DELETE FROM device_sessions WHERE account_id=?`, id)
	_, err := s.db.Exec(`DELETE FROM accounts WHERE id=? AND active=0`, id)
	if err != nil {
		return err
	}
	return s.SealNow()
}

// AbandonEnrollment deletes an inactive account if the password matches.
func (s *Store) AbandonEnrollment(username, password string, verify func(encoded, password string) bool) error {
	acc, err := s.GetAccountByUsername(username)
	if err != nil {
		return err
	}
	if acc.Active {
		return ErrConflict
	}
	if !verify(acc.PasswordHash, password) {
		return ErrDenied
	}
	return s.deleteAccountRow(acc.ID)
}

func isUnique(err error) bool {
	return err != nil && (contains(err.Error(), "UNIQUE") || contains(err.Error(), "unique"))
}

func contains(s, sub string) bool {
	return len(s) >= len(sub) && (s == sub || len(sub) == 0 ||
		(func() bool {
			for i := 0; i+len(sub) <= len(s); i++ {
				if s[i:i+len(sub)] == sub {
					return true
				}
			}
			return false
		})())
}

func (s *Store) ConfirmTOTP(username, code string, validate func(secret, code string) bool) error {
	acc, err := s.GetAccountByUsername(username)
	if err != nil {
		return err
	}
	if acc.Active {
		return ErrConflict
	}
	if !acc.EnrollExpiresAt.IsZero() && !nowUTC().Before(acc.EnrollExpiresAt) {
		_ = s.deleteAccountRow(acc.ID)
		return ErrNotFound
	}
	secret, err := s.decryptCol(acc.TOTPEnc)
	if err != nil {
		return err
	}
	if !validate(secret, code) {
		return ErrDenied
	}
	_, err = s.db.Exec(`UPDATE accounts SET active=1, enroll_expires_at='' WHERE id=?`, acc.ID)
	if err != nil {
		return err
	}
	return s.SealNow()
}

func scanAccount(row interface{ Scan(dest ...any) error }) (*Account, error) {
	var a Account
	var active int
	var created, enrollExp string
	if err := row.Scan(&a.ID, &a.Username, &a.PasswordHash, &a.TOTPEnc, &active, &a.Pubkey, &created, &enrollExp); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	a.Active = active == 1
	a.CreatedAt, _ = parseTime(created)
	if enrollExp != "" {
		a.EnrollExpiresAt, _ = parseTime(enrollExp)
	}
	return &a, nil
}

func (s *Store) GetAccountByUsername(username string) (*Account, error) {
	row := s.db.QueryRow(
		`SELECT id,username,password_hash,totp_enc,active,pubkey,created_at,COALESCE(enroll_expires_at,'') FROM accounts WHERE username=? COLLATE NOCASE`,
		username,
	)
	return scanAccount(row)
}

func (s *Store) GetAccountByID(id string) (*Account, error) {
	row := s.db.QueryRow(
		`SELECT id,username,password_hash,totp_enc,active,pubkey,created_at,COALESCE(enroll_expires_at,'') FROM accounts WHERE id=?`,
		id,
	)
	return scanAccount(row)
}

func (s *Store) TOTPSecret(acc *Account) (string, error) {
	return s.decryptCol(acc.TOTPEnc)
}

func (s *Store) SetPubkey(accountID, pubkey string) error {
	_, err := s.db.Exec(`UPDATE accounts SET pubkey=? WHERE id=?`, pubkey, accountID)
	if err != nil {
		return err
	}
	return s.SealNow()
}

func (s *Store) CreatePendingLogin(accountID, deviceID, assertion string, ttl time.Duration) (*PendingLogin, error) {
	// expire old
	_, _ = s.db.Exec(`UPDATE pending_device_logins SET status='denied' WHERE account_id=? AND status='pending' AND expires_at < ?`,
		accountID, fmtTime(nowUTC()))
	id := uuid.NewString()
	t := nowUTC()
	exp := t.Add(ttl)
	_, err := s.db.Exec(
		`INSERT INTO pending_device_logins(id,account_id,device_id,assertion,status,token_once,expires_at,created_at) VALUES(?,?,?,?,'pending','',?,?)`,
		id, accountID, deviceID, assertion, fmtTime(exp), fmtTime(t),
	)
	if err != nil {
		return nil, err
	}
	_ = s.SealNow()
	return &PendingLogin{
		ID: id, AccountID: accountID, DeviceID: deviceID, Assertion: assertion,
		Status: "pending", ExpiresAt: exp, CreatedAt: t,
	}, nil
}

func (s *Store) GetPending(id string) (*PendingLogin, error) {
	row := s.db.QueryRow(
		`SELECT id,account_id,device_id,assertion,status,token_once,expires_at,created_at FROM pending_device_logins WHERE id=?`,
		id,
	)
	var p PendingLogin
	var exp, created string
	if err := row.Scan(&p.ID, &p.AccountID, &p.DeviceID, &p.Assertion, &p.Status, &p.TokenOnce, &exp, &created); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	p.ExpiresAt, _ = parseTime(exp)
	p.CreatedAt, _ = parseTime(created)
	if p.Status == "pending" && nowUTC().After(p.ExpiresAt) {
		_, _ = s.db.Exec(`UPDATE pending_device_logins SET status='denied' WHERE id=?`, id)
		p.Status = "denied"
	}
	return &p, nil
}

// ConsumePendingPoll returns status; if approved, returns device token once then clears it.
func (s *Store) ConsumePendingPoll(id string) (status string, deviceToken string, err error) {
	p, err := s.GetPending(id)
	if err != nil {
		return "", "", err
	}
	if p.Status == "approved" && p.TokenOnce != "" {
		tok := p.TokenOnce
		_, err = s.db.Exec(`UPDATE pending_device_logins SET token_once='' WHERE id=?`, id)
		if err != nil {
			return "", "", err
		}
		_ = s.SealNow()
		return "approved", tok, nil
	}
	return p.Status, "", nil
}

// ReleasePending approves or denies; on approve creates device session (replacing any existing).
func (s *Store) ReleasePending(pendingID string, approve bool, mintToken func() (plain string, hash string, err error)) (string, error) {
	p, err := s.GetPending(pendingID)
	if err != nil {
		return "", err
	}
	if p.Status != "pending" {
		return "", ErrConflict
	}
	if nowUTC().After(p.ExpiresAt) {
		_, _ = s.db.Exec(`UPDATE pending_device_logins SET status='denied' WHERE id=?`, pendingID)
		return "", ErrPendingExpired
	}
	if !approve {
		_, err = s.db.Exec(`UPDATE pending_device_logins SET status='denied' WHERE id=?`, pendingID)
		if err != nil {
			return "", err
		}
		_ = s.SealNow()
		return "denied", nil
	}
	plain, hash, err := mintToken()
	if err != nil {
		return "", err
	}
	tx, err := s.db.Begin()
	if err != nil {
		return "", err
	}
	defer func() { _ = tx.Rollback() }()
	if _, err := tx.Exec(`DELETE FROM device_sessions WHERE account_id=?`, p.AccountID); err != nil {
		return "", err
	}
	sid := uuid.NewString()
	if _, err := tx.Exec(
		`INSERT INTO device_sessions(id,account_id,device_id,token_hash,created_at) VALUES(?,?,?,?,?)`,
		sid, p.AccountID, p.DeviceID, hash, fmtTime(nowUTC()),
	); err != nil {
		return "", err
	}
	if _, err := tx.Exec(
		`UPDATE pending_device_logins SET status='approved', token_once=? WHERE id=?`,
		plain, pendingID,
	); err != nil {
		return "", err
	}
	if err := tx.Commit(); err != nil {
		return "", err
	}
	_ = s.SealNow()
	return "approved", nil
}

func (s *Store) LookupDeviceToken(token string) (*DeviceSession, *Account, error) {
	hash := crypto.HashToken(token)
	row := s.db.QueryRow(
		`SELECT id,account_id,device_id,token_hash,COALESCE(push_token,''),created_at FROM device_sessions WHERE token_hash=?`,
		hash,
	)
	var d DeviceSession
	var created string
	if err := row.Scan(&d.ID, &d.AccountID, &d.DeviceID, &d.TokenHash, &d.PushToken, &created); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil, ErrNotFound
		}
		return nil, nil, err
	}
	d.CreatedAt, _ = parseTime(created)
	acc, err := s.GetAccountByID(d.AccountID)
	if err != nil {
		return nil, nil, err
	}
	return &d, acc, nil
}

func (s *Store) SetPushToken(sessionToken, pushToken string) error {
	hash := crypto.HashToken(sessionToken)
	res, err := s.db.Exec(`UPDATE device_sessions SET push_token=? WHERE token_hash=?`, pushToken, hash)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return ErrNotFound
	}
	return s.SealNow()
}

func (s *Store) PushTokenForAccount(accountID string) (string, error) {
	var tok string
	err := s.db.QueryRow(`SELECT COALESCE(push_token,'') FROM device_sessions WHERE account_id=?`, accountID).Scan(&tok)
	if errors.Is(err, sql.ErrNoRows) {
		return "", nil
	}
	return tok, err
}

func (s *Store) RevokeByToken(token string) error {
	hash := crypto.HashToken(token)
	res, err := s.db.Exec(`DELETE FROM device_sessions WHERE token_hash=?`, hash)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return ErrNotFound
	}
	return s.SealNow()
}

func (s *Store) RevokeByAccount(accountID string) error {
	_, err := s.db.Exec(`DELETE FROM device_sessions WHERE account_id=?`, accountID)
	if err != nil {
		return err
	}
	return s.SealNow()
}

func (s *Store) HasDeviceSession(accountID string) (bool, error) {
	var n int
	err := s.db.QueryRow(`SELECT COUNT(1) FROM device_sessions WHERE account_id=?`, accountID).Scan(&n)
	return n > 0, err
}

func (s *Store) InsertMessage(recipientID, senderUsername string, ciphertext []byte, ttl time.Duration) (*Message, error) {
	id := uuid.NewString()
	t := nowUTC()
	exp := t.Add(ttl)
	_, err := s.db.Exec(
		`INSERT INTO messages(id,recipient_account_id,sender_username,ciphertext,created_at,expires_at) VALUES(?,?,?,?,?,?)`,
		id, recipientID, senderUsername, ciphertext, fmtTime(t), fmtTime(exp),
	)
	if err != nil {
		return nil, err
	}
	_ = s.SealNow()
	return &Message{
		ID: id, RecipientAccID: recipientID, SenderUsername: senderUsername,
		Ciphertext: ciphertext, CreatedAt: t, ExpiresAt: exp,
	}, nil
}

// FetchAndDelete returns all non-expired messages for account and deletes them.
func (s *Store) FetchAndDelete(recipientID string) ([]Message, error) {
	now := fmtTime(nowUTC())
	rows, err := s.db.Query(
		`SELECT id,recipient_account_id,sender_username,ciphertext,created_at,expires_at FROM messages
		 WHERE recipient_account_id=? AND expires_at > ? ORDER BY created_at ASC`,
		recipientID, now,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Message
	var ids []string
	for rows.Next() {
		var m Message
		var c, e string
		if err := rows.Scan(&m.ID, &m.RecipientAccID, &m.SenderUsername, &m.Ciphertext, &c, &e); err != nil {
			return nil, err
		}
		m.CreatedAt, _ = parseTime(c)
		m.ExpiresAt, _ = parseTime(e)
		out = append(out, m)
		ids = append(ids, m.ID)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	for _, id := range ids {
		if _, err := s.db.Exec(`DELETE FROM messages WHERE id=?`, id); err != nil {
			return nil, err
		}
	}
	if len(ids) > 0 {
		_ = s.SealNow()
	}
	return out, nil
}

func (s *Store) PurgeExpired(now time.Time) (int64, error) {
	res, err := s.db.Exec(`DELETE FROM messages WHERE expires_at <= ?`, fmtTime(now))
	if err != nil {
		return 0, err
	}
	n, _ := res.RowsAffected()
	_, _ = s.db.Exec(`UPDATE pending_device_logins SET status='denied' WHERE status='pending' AND expires_at <= ?`, fmtTime(now))
	// Unfinished TOTP enrollments release the username.
	rows, err := s.db.Query(`SELECT id FROM accounts WHERE active=0 AND (enroll_expires_at='' OR enroll_expires_at <= ?)`, fmtTime(now))
	if err != nil {
		return n, err
	}
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err == nil {
			ids = append(ids, id)
		}
	}
	_ = rows.Close()
	for _, id := range ids {
		if err := s.deleteAccountRow(id); err != nil {
			return n, err
		}
		n++
	}
	if n > 0 {
		_ = s.SealNow()
	}
	return n, nil
}

// SealedBytes returns the on-disk sealed file for tests.
func (s *Store) SealedBytes() ([]byte, error) {
	return os.ReadFile(s.sealed)
}

// CiphertextB64 helper for API.
func CiphertextB64(b []byte) string {
	return base64.StdEncoding.EncodeToString(b)
}

func DecodeCiphertextB64(s string) ([]byte, error) {
	return base64.StdEncoding.DecodeString(s)
}
