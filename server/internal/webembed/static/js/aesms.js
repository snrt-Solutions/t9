async function api(path, opts = {}) {
  const res = await fetch(path, {
    ...opts,
    headers: {
      "Content-Type": "application/json",
      ...(opts.headers || {}),
    },
    credentials: "omit",
  });
  const text = await res.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = { raw: text }; }
  if (!res.ok) {
    const err = new Error((data && data.error) || res.statusText);
    err.status = res.status;
    err.data = data;
    throw err;
  }
  return data;
}

function setStatus(el, msg, kind) {
  if (!el) return;
  el.textContent = msg || "";
  el.classList.remove("ok", "err");
  if (kind) el.classList.add(kind);
}

function qs(name) {
  return new URLSearchParams(location.search).get(name);
}

function pngDataURLToBlobURL(dataURL) {
  const prefix = "data:image/png;base64,";
  if (!dataURL || !dataURL.startsWith(prefix)) return "";
  try {
    const bin = atob(dataURL.slice(prefix.length));
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return URL.createObjectURL(new Blob([bytes], { type: "image/png" }));
  } catch {
    return dataURL;
  }
}

function drawQRFromURI(canvas, uri, size) {
  if (!uri || !canvas) return false;
  const lib = window.QRCode;
  if (!lib || typeof lib.toCanvas !== "function") return false;
  try {
    lib.toCanvas(canvas, uri, { width: size || 220, margin: 2, errorCorrectionLevel: "M" });
    return true;
  } catch {
    return false;
  }
}

function mountTOTPQR(box, data) {
  if (!box) return false;
  box.replaceChildren();
  const uri = data && data.totp_uri ? String(data.totp_uri) : "";
  const png = data && data.totp_qr_png ? String(data.totp_qr_png) : "";

  const addOpenLink = () => {
    if (!uri.startsWith("otpauth://")) return;
    const a = document.createElement("a");
    a.className = "qr-open";
    a.href = uri;
    a.textContent = "Or open in authenticator app";
    box.appendChild(a);
  };

  const showCanvas = () => {
    const canvas = document.createElement("canvas");
    canvas.width = 220;
    canvas.height = 220;
    box.appendChild(canvas);
    if (drawQRFromURI(canvas, uri, 220)) {
      addOpenLink();
      return true;
    }
    canvas.remove();
    return false;
  };

  if (png) {
    const img = document.createElement("img");
    img.alt = "TOTP enrollment QR code";
    img.width = 220;
    img.height = 220;
    img.decoding = "sync";
    img.src = pngDataURLToBlobURL(png) || png;
    img.onerror = () => {
      box.replaceChildren();
      if (!showCanvas()) {
        box.textContent = "QR unavailable. Type the secret below.";
      }
    };
    box.appendChild(img);
    addOpenLink();
    return true;
  }
  if (showCanvas()) return true;
  if (uri.startsWith("otpauth://")) {
    addOpenLink();
    return false;
  }
  box.textContent = "QR unavailable. Type the secret below.";
  return false;
}
