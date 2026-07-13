// Print the resolved E2B API key (env first, then plugin config [secrets]).
// Used by bash scripts to feed the key to the `e2b` CLI without ~/.zshrc.
// Prints nothing (exit 0) if no key is configured.
import { loadConfig } from "./config.js"

const key = loadConfig().apiKey
if (key) process.stdout.write(key)
