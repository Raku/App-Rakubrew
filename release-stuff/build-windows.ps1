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

mkdir -Force download
mkdir -Force strawberry

# Install Git -- commented out for now, as CircleCI already has git installed
#Invoke-WebRequest https://github.com/git-for-windows/git/releases/download/v2.24.0-rc1.windows.1/MinGit-2.24.0.rc1.windows.1-64-bit.zip -OutFile C:/download/mingit.zip
#Expand-Archive -Path C:/download/mingit.zip -DestinationPath C:/git
#mv C:/git/etc/gitconfig C:/git/etc/gitconfig.broken
#$Env:PATH = "C:\git\cmd;$Env:PATH"

# Install Perl
Remove-Item Env:PERL5LIB -ErrorAction Ignore

$strawberry = "download/strawberry-perl-5.30.0.1-64bit.zip"
If(!(test-path $strawberry)) {
    Invoke-WebRequest http://strawberryperl.com/download/5.30.0.1/strawberry-perl-5.30.0.1-64bit.zip -OutFile $strawberry
}

If(!(test-path "strawberry/README.txt")) {
    Expand-Archive -Path $strawberry -DestinationPath strawberry
}

strawberry\relocation.pl.bat
$Env:PATH = (Join-Path -Path $repoPath -ChildPath "\strawberry\perl\bin") + ";" + (Join-Path -Path $repoPath -ChildPath "\strawberry\perl\site\bin") + ";" + (Join-Path -Path $repoPath -ChildPath "\strawberry\c\bin") + ";$Env:PATH"


cp resources/Config.pm.tmpl lib/App/Rakubrew/Config.pm
perl -pi -E 's/<\%distro_format\%>/win/' lib/App/Rakubrew/Config.pm
CheckLastExitCode

cpanm -n PAR::Packer
CheckLastExitCode

cpanm --installdeps -n .
CheckLastExitCode

cpanm --installdeps -n --cpanfile cpanfile.win .
CheckLastExitCode

pp -I lib -M App::Rakubrew:: -M HTTP::Tinyish:: -M IO::Socket::SSL -o rakubrew.exe script/rakubrew
CheckLastExitCode

# Reset our modified Config.pm again.
git checkout -f lib/App/Rakubrew/Config.pm

