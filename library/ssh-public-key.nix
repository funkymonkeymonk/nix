builtins.replaceStrings ["\n" "\r"] ["" ""] (builtins.readFile ../keys/monkey-ssh.pub)
