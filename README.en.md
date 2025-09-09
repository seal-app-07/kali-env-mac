> **⚠️ This document was assisted by AI.**
> Please verify before applying. Issues/PRs are welcome.

# pentest-mac

A repository to set up **Kali Linux on macOS** in a **reproducible** way.  
Install Kali **minimally in a VM**, then use **one bootstrap** to reach a full desktop with browser and common tools.

## Goals

- **Reproducibility** for third parties
- **Simplicity**: start minimal, add only what’s needed
- **Maintainability**: IME/keyboard/shared folder/shortcuts in one place
- **Robustness**: include safeguards for common initramfs/plymouth pitfalls

## Layout

```
.
├─ vm/                # VM flow & scripts
│  ├─ README.md       # Japanese guide
│  ├─ README.en.md    # English guide
│  └─ kali/           # scripts (kali-*.sh)
└─ container/         # optional container flavor
```

