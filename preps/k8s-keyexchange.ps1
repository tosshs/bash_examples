# k8s-keyexchange.ps1
$u="tosshs"; $c="192.168.85.200"; $w="192.168.85.210"
$d="$HOME\.ssh"; $k="$d\id_ed25519"; $p="$k.pub"
mkdir $d -Force | Out-Null
if(!(Test-Path $k)){ cmd /c "ssh-keygen -t ed25519 -f `"$k`" -N `"`" -C k8s >nul" }

ssh-keygen -R $c *> $null; ssh-keygen -R $w *> $null
$pk=(Get-Content $p -Raw).Trim()

$push = {
  param($h)
  $cmd = "mkdir -p ~/.ssh; chmod 700 ~/.ssh; touch ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys; " +
         "grep -qxF '$pk' ~/.ssh/authorized_keys; if [ `$? -ne 0 ]; then echo '$pk' >> ~/.ssh/authorized_keys; fi"
  ssh -o StrictHostKeyChecking=accept-new "$u@$h" "sh -lc `"$cmd`""
}

& $push $c; & $push $w
ssh -o BatchMode=yes -o ConnectTimeout=5 "$u@$c" "echo control OK"
ssh -o BatchMode=yes -o ConnectTimeout=5 "$u@$w" "echo worker OK"
