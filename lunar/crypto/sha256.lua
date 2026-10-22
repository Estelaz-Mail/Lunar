local sha256 = {}

local MASK = 0xffffffff

local K = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local function rotate_right(value, bits)
  return ((value >> bits) | (value << (32 - bits))) & MASK
end

function sha256.digest(message)
  local h = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
              0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }

  local length = #message
  local padding = (56 - (length + 1) % 64) % 64
  local padded = message .. "\128" .. string.rep("\0", padding)
    .. string.pack(">I8", length * 8)

  local w = {}
  for block = 1, #padded, 64 do
    for index = 1, 16 do
      w[index] = string.unpack(">I4", padded, block + (index - 1) * 4)
    end
    for index = 17, 64 do
      local s0 = rotate_right(w[index - 15], 7) ~ rotate_right(w[index - 15], 18)
        ~ (w[index - 15] >> 3)
      local s1 = rotate_right(w[index - 2], 17) ~ rotate_right(w[index - 2], 19)
        ~ (w[index - 2] >> 10)
      w[index] = (w[index - 16] + s0 + w[index - 7] + s1) & MASK
    end

    local a, b, c, d, e, f, g, hh = h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]
    for index = 1, 64 do
      local s1 = rotate_right(e, 6) ~ rotate_right(e, 11) ~ rotate_right(e, 25)
      local choice = (e & f) ~ ((~e & MASK) & g)
      local temp1 = (hh + s1 + choice + K[index] + w[index]) & MASK
      local s0 = rotate_right(a, 2) ~ rotate_right(a, 13) ~ rotate_right(a, 22)
      local majority = (a & b) ~ (a & c) ~ (b & c)
      local temp2 = (s0 + majority) & MASK
      hh, g, f, e = g, f, e, (d + temp1) & MASK
      d, c, b, a = c, b, a, (temp1 + temp2) & MASK
    end

    h[1] = (h[1] + a) & MASK
    h[2] = (h[2] + b) & MASK
    h[3] = (h[3] + c) & MASK
    h[4] = (h[4] + d) & MASK
    h[5] = (h[5] + e) & MASK
    h[6] = (h[6] + f) & MASK
    h[7] = (h[7] + g) & MASK
    h[8] = (h[8] + hh) & MASK
  end

  local out = {}
  for index = 1, 8 do out[index] = string.pack(">I4", h[index]) end
  return table.concat(out)
end

function sha256.hex(digest)
  return (digest:gsub(".", function(char) return string.format("%02x", char:byte()) end))
end

return sha256
