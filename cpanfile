requires 'Try::Tiny'             => '0.30';
requires 'File::Which'           => '1.23';
requires 'HTTP::Tinyish'         => '0.15';
requires 'File::HomeDir'         => '0.97';
requires 'Encode::Locale'        => '1.05';
requires 'JSON'                  => '4.02';
requires 'File::Copy::Recursive' => '0.45';

on 'test' => sub {
  requires 'Test::Compile', '2.3.1';
};

