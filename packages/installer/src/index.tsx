import React, { useState, useEffect } from 'react';
import { render, Box, Text, useInput, useApp } from 'ink';
import TextInput from 'ink-text-input';
import SelectInput from 'ink-select-input';
import { execSync } from 'child_process';
import https from 'https';

const FLAKE_URL = 'github:funkymonkeymonk/nix';

interface User {
  name: string;
  email: string;
}

const users: User[] = [
  { name: 'monkey', email: 'me@willweaver.dev' },
  { name: 'wweaver', email: 'wweaver@justworks.com' },
];

type Mode = 'unknown' | 'liveusb' | 'existing';
type Step = 'welcome' | 'hostname' | 'admin' | 'review' | 'installing' | 'complete' | 'error';

const detectMode = (): Mode => {
  try {
    if (require('fs').existsSync('/home/nixos') && require('fs').existsSync('/nix/store')) {
      if (require('fs').existsSync('/etc/NIXOS')) {
        if (!require('fs').existsSync('/home/monkey') && !require('fs').existsSync('/home/wweaver')) {
          return 'liveusb';
        }
      }
    }
    
    if (require('fs').existsSync('/etc/NIXOS') && require('fs').existsSync('/home')) {
      return 'existing';
    }
  } catch {}
  
  return 'unknown';
};

const checkRoot = () => {
  if (process.getuid && process.getuid() !== 0) {
    console.error('Error: This installer must be run as root');
    console.error('Run with: sudo nix run github:funkymonkeymonk/nix#installer');
    process.exit(1);
  }
};

const fetchTargets = async (): Promise<string[]> => {
  return new Promise((resolve) => {
    https.get('https://api.github.com/repos/funkymonkeymonk/nix/git/trees/main?recursive=1', {
      headers: { 'User-Agent': 'nixos-installer' }
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          const targets: string[] = [];
          const seen = new Set<string>();
          
          for (const item of json.tree || []) {
            if (item.path.startsWith('targets/') && item.path.endsWith('/default.nix')) {
              const target = item.path.split('/')[1];
              if (!seen.has(target)) {
                targets.push(target);
                seen.add(target);
              }
            }
          }
          
          resolve(targets);
        } catch {
          resolve([]);
        }
      });
    }).on('error', () => resolve([]));
  });
};

const WelcomeStep = ({ mode, onContinue }: { mode: Mode; onContinue: () => void }) => {
  useInput((input, key) => {
    if (key.return) onContinue();
  });

  const modeText = mode === 'liveusb' ? 'Live USB (Fresh Install)' : 
                   mode === 'existing' ? 'Existing NixOS System' : 
                   'Unknown';

  return (
    <Box flexDirection="column" padding={1}>
      <Text bold color="magenta">NixOS Flake Installer</Text>
      <Text color="gray">{FLAKE_URL}</Text>
      <Box marginTop={1}>
        <Text bold>Detected Mode: </Text>
        <Text>{modeText}</Text>
      </Box>
      {mode === 'unknown' ? (
        <Box marginTop={1}>
          <Text color="red">Error: Could not detect installation mode</Text>
          <Text>This must be run from NixOS Live USB or an existing NixOS system</Text>
        </Box>
      ) : (
        <Box marginTop={1}>
          <Text color="cyan">Press Enter to continue...</Text>
        </Box>
      )}
    </Box>
  );
};

const HostnameStep = ({ onSubmit }: { onSubmit: (hostname: string) => void }) => {
  const [value, setValue] = useState('');

  return (
    <Box flexDirection="column" padding={1}>
      <Text bold color="magenta">Step 1: Hostname</Text>
      <Box marginTop={1}>
        <Text>Enter hostname for this machine:</Text>
      </Box>
      <Box marginTop={1}>
        <TextInput
          value={value}
          onChange={setValue}
          onSubmit={() => onSubmit(value || 'nixos')}
          placeholder="drlight"
        />
      </Box>
    </Box>
  );
};

const AdminStep = ({ onSubmit }: { onSubmit: (user: User) => void }) => {
  const items = users.map((u, index) => ({
    label: `${u.name} (${u.email})`,
    value: u,
  }));

  return (
    <Box flexDirection="column" padding={1}>
      <Text bold color="magenta">Step 2: Admin User</Text>
      <Box marginTop={1}>
        <Text>Select an admin user:</Text>
      </Box>
      <Box marginTop={1}>
        <SelectInput
          items={items}
          onSelect={(item) => onSubmit(item.value)}
        />
      </Box>
    </Box>
  );
};

const ReviewStep = ({ 
  hostname, 
  adminUser, 
  targetExists, 
  mode,
  onConfirm 
}: { 
  hostname: string; 
  adminUser: User; 
  targetExists: boolean;
  mode: Mode;
  onConfirm: () => void;
}) => {
  useInput((input, key) => {
    if (key.return) onConfirm();
  });

  return (
    <Box flexDirection="column" padding={1}>
      <Text bold color="magenta">Review Configuration</Text>
      <Box marginTop={1} flexDirection="column">
        <Text><Text bold>Hostname: </Text>{hostname}</Text>
        <Text><Text bold>Admin User: </Text>{adminUser.name} ({adminUser.email})</Text>
        <Text>
          <Text bold>Target Exists: </Text>
          <Text color={targetExists ? 'green' : 'yellow'}>
            {targetExists ? 'Yes' : 'No (will use bootstrap)'}
          </Text>
        </Text>
        <Text><Text bold>Mode: </Text>{mode === 'liveusb' ? 'Fresh Install' : 'Apply to Existing'}</Text>
        <Text><Text bold>Flake: </Text>{FLAKE_URL}</Text>
      </Box>
      <Box marginTop={1}>
        <Text color="cyan">Press Enter to proceed...</Text>
      </Box>
    </Box>
  );
};

const InstallingStep = ({ mode }: { mode: Mode }) => {
  const [dots, setDots] = useState('');

  useEffect(() => {
    const interval = setInterval(() => {
      setDots(d => d.length >= 3 ? '' : d + '.');
    }, 500);
    return () => clearInterval(interval);
  }, []);

  return (
    <Box flexDirection="column" padding={1}>
      <Text bold color="magenta">Installing{dots}</Text>
      <Box marginTop={1}>
        <Text>
          {mode === 'liveusb' 
            ? 'Running nixos-install...' 
            : 'Running nixos-rebuild switch...'}
        </Text>
      </Box>
      <Box marginTop={1}>
        <Text color="gray">This may take several minutes...</Text>
      </Box>
    </Box>
  );
};

const CompleteStep = ({ 
  hostname, 
  adminUser, 
  mode, 
  targetExists 
}: { 
  hostname: string; 
  adminUser: User; 
  mode: Mode;
  targetExists: boolean;
}) => {
  useInput((input, key) => {
    if (key.return) process.exit(0);
  });

  return (
    <Box flexDirection="column" padding={1}>
      <Text bold color="green">✓ Installation Complete!</Text>
      <Box marginTop={1} flexDirection="column">
        {mode === 'liveusb' ? (
          <>
            <Text>1. Reboot: <Text bold>reboot</Text></Text>
            <Text>2. SSH: <Text bold>ssh {adminUser.name}@{hostname}</Text></Text>
            {!targetExists && (
              <Box marginTop={1} flexDirection="column">
                <Text color="yellow">Note: Bootstrap configuration installed!</Text>
                <Text>Create a proper target in the flake repo.</Text>
              </Box>
            )}
          </>
        ) : (
          <>
            <Text>Configuration applied successfully!</Text>
            <Text>System will auto-upgrade daily from: {FLAKE_URL}</Text>
          </>
        )}
      </Box>
      <Box marginTop={1}>
        <Text color="cyan">Press Enter to exit...</Text>
      </Box>
    </Box>
  );
};

const ErrorStep = ({ error }: { error: string }) => {
  useInput((input, key) => {
    if (key.return) process.exit(1);
  });

  return (
    <Box flexDirection="column" padding={1}>
      <Text bold color="red">✗ Installation Failed</Text>
      <Box marginTop={1}>
        <Text>{error}</Text>
      </Box>
      <Box marginTop={1}>
        <Text color="cyan">Press Enter to exit...</Text>
      </Box>
    </Box>
  );
};

const App = () => {
  const [step, setStep] = useState<Step>('welcome');
  const [mode, setMode] = useState<Mode>('unknown');
  const [hostname, setHostname] = useState('');
  const [adminUser, setAdminUser] = useState<User>(users[0]);
  const [targetExists, setTargetExists] = useState(false);
  const [targets, setTargets] = useState<string[]>([]);
  const [error, setError] = useState('');

  useEffect(() => {
    checkRoot();
    const detectedMode = detectMode();
    setMode(detectedMode);
    
    fetchTargets().then(t => {
      setTargets(t);
    });
  }, []);

  const runInstall = async () => {
    try {
      if (mode === 'liveusb') {
        // Generate hardware config
        const { mkdirSync, writeFileSync } = require('fs');
        mkdirSync('/mnt/etc/nixos', { recursive: true });
        
        const hwConfig = execSync('nixos-generate-config --root /mnt --show-hardware-config');
        writeFileSync('/mnt/etc/nixos/hardware-configuration.nix', hwConfig);
        
        // Install
        execSync(`nixos-install --no-root-passwd --root /mnt --flake ${FLAKE_URL}#${hostname}`, {
          stdio: 'inherit'
        });
      } else {
        // Apply to existing
        execSync(`nixos-rebuild switch --flake ${FLAKE_URL}#${hostname}`, {
          stdio: 'inherit'
        });
      }
      
      setStep('complete');
    } catch (e: any) {
      setError(e.message || 'Installation failed');
      setStep('error');
    }
  };

  switch (step) {
    case 'welcome':
      return <WelcomeStep mode={mode} onContinue={() => setStep('hostname')} />;
    
    case 'hostname':
      return <HostnameStep onSubmit={(h) => {
        setHostname(h);
        setTargetExists(targets.includes(h));
        setStep('admin');
      }} />;
    
    case 'admin':
      return <AdminStep onSubmit={(u) => {
        setAdminUser(u);
        setStep('review');
      }} />;
    
    case 'review':
      return <ReviewStep
        hostname={hostname}
        adminUser={adminUser}
        targetExists={targetExists}
        mode={mode}
        onConfirm={() => {
          setStep('installing');
          runInstall();
        }}
      />;
    
    case 'installing':
      return <InstallingStep mode={mode} />;
    
    case 'complete':
      return <CompleteStep
        hostname={hostname}
        adminUser={adminUser}
        mode={mode}
        targetExists={targetExists}
      />;
    
    case 'error':
      return <ErrorStep error={error} />;
    
    default:
      return null;
  }
};

render(<App />);
