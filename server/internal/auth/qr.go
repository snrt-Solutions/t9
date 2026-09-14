package auth

import (
	"bytes"
	"encoding/base64"
	"image"
	"image/png"

	"github.com/boombuler/barcode"
	"github.com/boombuler/barcode/qr"
)

const (
	qrQuietModules = 4
	qrModulePx     = 8
)

// TOTPQRDataURL returns a PNG data URL for an otpauth URI so the web UI
// never depends on a third-party QR library.
func TOTPQRDataURL(otpauthURI string) (string, error) {
	code, err := qr.Encode(otpauthURI, qr.M, qr.Auto)
	if err != nil {
		return "", err
	}
	img := renderQR(code, qrModulePx, qrQuietModules)
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		return "", err
	}
	return "data:image/png;base64," + base64.StdEncoding.EncodeToString(buf.Bytes()), nil
}

// renderQR draws a scannable QR: integer module scaling plus a 4-module quiet zone.
// barcode.Scale to a fixed 256px leaves almost no border, which authenticators reject.
func renderQR(code barcode.Barcode, modulePx, quietModules int) *image.Gray {
	if modulePx < 1 {
		modulePx = 1
	}
	if quietModules < 0 {
		quietModules = 0
	}
	n := code.Bounds().Dx()
	dim := (n + quietModules*2) * modulePx
	dst := image.NewGray(image.Rect(0, 0, dim, dim))
	for i := range dst.Pix {
		dst.Pix[i] = 255
	}
	off := quietModules * modulePx
	for y := 0; y < n; y++ {
		for x := 0; x < n; x++ {
			r, _, _, _ := code.At(x, y).RGBA()
			if r >= 0x8000 {
				continue
			}
			px := off + x*modulePx
			py := off + y*modulePx
			for dy := 0; dy < modulePx; dy++ {
				row := (py + dy) * dim
				for dx := 0; dx < modulePx; dx++ {
					dst.Pix[row+px+dx] = 0
				}
			}
		}
	}
	return dst
}
