#!/bin/bash
set -eou pipefail

cat << ENDL
      ____  ___   _     ____________
     / __ \/   | ( )  _/_/ ____/ __ \\ 
    / / / / /| |  V _/_//___ \/ / / /
   / /_/ / ___ |  _/_/ ____/ / /_/ /
  /_____/_/  |_| /_/  /_____/\____/

      Keeping AI Productive 
    50 Days In And Beyond
                                                                          
ENDL
insdir=$(mktemp -d)
if ! command -v git > /dev/null; then
    curl -Ls https://github.com/day50-dev/tmux-ai-agent-helper/archive/refs/heads/main.zip -o $insdir/main.zip
    cd $insdir && unzip main.zip
    cd tmux-ai-agent-helper-main/ && ./install.sh
else
    rm -r $insdir
    git clone --quiet https://github.com/day50-dev/sidechat $insdir
    $insdir/install.sh
fi
rm -fr $insdir
