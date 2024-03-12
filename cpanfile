requires 'Try::Tiny'             => '== 0.31';
requires 'File::Which'           => '== 1.27';
requires 'HTTP::Tinyish'         => '== 0.19';
requires 'File::HomeDir'         => '== 1.006';
requires 'Encode::Locale'        => '== 1.05';
requires 'JSON'                  => '== 4.10';
requires 'File::Copy::Recursive' => '== 0.45';

on 'test' => sub {
  requires 'Test::Compile', '== 3.3.1';
};

