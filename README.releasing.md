Windows
=======

- download Docker desktop and install in Windows mode
- In a PowerShell

    docker pull mcr.microsoft.com/windows/nanoserver:1903
    docker run -it mcr.microsoft.com/windows/nanoserver:1903 cmd.exe
    
- In the container

    mkdir C:/download
    mkdir C:/git
    mkdir C:/strawberry
    
    Invoke-WebRequest http://strawberryperl.com/download/5.30.0.1/strawberry-perl-5.30.0.1-64bit.zip -OutFile C:/download/strawberry-perl-5.30.0.1-64bit.zip
    Expand-Archive -Path C:/download/strawberry-perl-5.30.0.1-64bit.zip -DestinationPath C:\strawberry
    .\strawberry\relocation.pl.bat
    $Env:PATH = "C:\strawberry\perl\bin;C:\strawberry\perl\site\bin;$Env:PATH"
    
    Invoke-WebRequest https://github.com/git-for-windows/git/releases/download/v2.24.0-rc1.windows.1/MinGit-2.24.0.rc1.windows.1-64-bit.zip -OutFile C:/download/mingit.zip
    Expand-Archive -Path C:/download/mingit.zip -DestinationPath C:/git
    mv C:/git/etc/gitconfig C:/git/etc/gitconfig.broken
    $Env:PATH = "C:\git\cmd;$Env:PATH"
    
    cpanm -n PAR::Packer
    
    git clone https://github.com/patzim/rakudobrew.git App-Rakudobrew
    
    # cpanm --installdeps -n App-Rakudobrew
    
    pp -I App-Rakudobrew/lib -M App::Rakudobrew::Shell::* -o rakudobrew.exe App-Rakudobrew/script/rakudobrew
    
    
    # Probably already part of strawberry
    # curl -L https://cpanmin.us | perl - App::cpanminus