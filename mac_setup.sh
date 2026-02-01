/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
brew install sdkman curl -s "https://get.sdkman.io" | bash
curl -s "https://get.sdkman.io" | bash
curl https://install.duckdb.org | sh

brew install git
brew install tmux
brew install nvim
brew install kind
brew install kubectl
brew install python3
brew install awsume
brew install sdkman curl -s "https://get.sdkman.io" | bash
brew install htop
brew install k9s
brew install teleport
brew install tig

# On macOS and Linux.
curl -LsSf https://astral.sh/uv/install.sh | sh
