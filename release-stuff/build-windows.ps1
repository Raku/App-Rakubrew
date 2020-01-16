$ErrorActionPreference = "Stop"

# Don't display progressbars when doing Invoke-WebRequest and similar.
# That would cause the command to fail, because in the CircleCI environment
# one can't modify the display.
# "Win32 internal error “Access is denied” 0x5 occurred while reading the console output buffer. Contact Microsoft Customer Support Services."
$progressPreference = 'silentlyContinue'

function CheckLastExitCode {
    if ($LastExitCode -ne 0) {
        $msg = @"
Program failed with: $LastExitCode
Callstack: $(Get-PSCallStack | Out-String)
"@
        throw $msg
    }
}

# cd to repo top level
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
$repoPath = (split-path -parent $scriptPath)
Set-Location $repoPath

mkdir download
mkdir strawberry

# Install Git -- commented out for now, as CircleCI already has git installed
#Invoke-WebRequest https://github.com/git-for-windows/git/releases/download/v2.24.0-rc1.windows.1/MinGit-2.24.0.rc1.windows.1-64-bit.zip -OutFile C:/download/mingit.zip
#Expand-Archive -Path C:/download/mingit.zip -DestinationPath C:/git
#mv C:/git/etc/gitconfig C:/git/etc/gitconfig.broken
#$Env:PATH = "C:\git\cmd;$Env:PATH"

# Install Perl
Invoke-WebRequest http://strawberryperl.com/download/5.30.0.1/strawberry-perl-5.30.0.1-64bit.zip -OutFile download/strawberry-perl-5.30.0.1-64bit.zip
Expand-Archive -Path download/strawberry-perl-5.30.0.1-64bit.zip -DestinationPath strawberry
strawberry\relocation.pl.bat
$Env:PATH = (Join-Path -Path $repoPath -ChildPath "\strawberry\perl\bin") + ";" + (Join-Path -Path $repoPath -ChildPath "\strawberry\perl\site\bin") + ";" + (Join-Path -Path $repoPath -ChildPath "\strawberry\c\bin") + ";$Env:PATH"


cp resources/Config.pm.tmpl lib/App/Rakubrew/Config.pm
perl -pi -E 's/<\%distro_format\%>/fatpack/' lib/App/Rakubrew/Config.pm

cpanm -n PAR::Packer
CheckLastExitCode

cpanm --installdeps -n .
CheckLastExitCode

cpanm --installdeps -n --cpanfile cpanfile.win .
CheckLastExitCode

pp -I lib -M App::Rakubrew::Shell::* -M IO::Socket::SSL -o rakubrew.exe script/rakubrew
CheckLastExitCode

