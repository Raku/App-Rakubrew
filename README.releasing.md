Release Guide
=============

- Bump version and create a respective commit
- Tag that commit with the version number
- Create a GitHub release
- Upload the release to CPAN
- Create `rakudobrew-win.exe` on Windows via the below instructions
- Create `rakudobrew-macos` on MacOS via the below instructions
- Create `rakudobrew-linux` on Linux via the below instructions
- Upload the the executables to the webserver in `$webroot/releases/{win,mac,linux}/{version}/rakudobrew(.exe)?`
- Bump the version number on the webserver in `$webroot/latest`


Linux
-----

    cpanm --installdeps -n .
    cpanm App::FatPacker
    fatpack trace script/rakudobrew
    for X in `ls -1 lib/App/Rakudobrew/Shell`; do echo App/Rakudobrew/Shell/$X >> fatpacker.trace; done
    fatpack packlists-for `cat fatpacker.trace` > packlists
    fatpack tree `cat packlists`
    fatpack file script/rakudobrew > rakudobrew.packed.pl



MacOS
-----

TBD


Windows
-------

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
    
    cpanm --installdeps -n App-Rakudobrew
    
    pp -I App-Rakudobrew/lib -M App::Rakudobrew::Shell::* -o rakudobrew.exe App-Rakudobrew/script/rakudobrew

