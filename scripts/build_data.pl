#!/usr/bin/perl
# Consolida as bases do TSE (candidatos 2026 BR+SP, complementar, bens, histórico, bens antigos)
use strict; use warnings; use utf8;
binmode STDOUT, ':utf8'; binmode STDERR, ':utf8';

sub rd {
  my ($f, $cb) = @_;
  open my $h, '<:encoding(latin1)', $f or die "$f: $!";
  my @h;
  while (my $l = <$h>) {
    # registro com quebra de linha dentro de aspas: junta até fechar as aspas
    while ((($l =~ tr/"//) % 2) && !eof($h)) { $l =~ s/\r?\n$/ /; $l .= <$h> }
    $l =~ s/\r?\n$//;
    my @x;
    while ($l =~ /\G(?:"((?:[^"]|"")*)"|([^;]*))(?:;|$)/g) { push @x, defined $1 ? $1 =~ s/""/"/gr : $2; last if pos($l) >= length $l }
    if (!@h) { @h = @x; next }
    my %r; @r{@h} = @x; $cb->(\%r);
  }
}
sub num { my $v = shift // ''; $v =~ s/\.//g if $v =~ /,/; $v =~ s/,/./; $v =~ /^-?[\d.]+$/ ? $v + 0 : 0 }
sub nul { my $v = shift; return undef if !defined $v || $v =~ /^#(NULO|NE)/ || $v eq '-1' || $v eq '-3'; $v }
sub js {
  my $d = shift;
  if (ref $d eq 'HASH') { return '{' . join(',', map { "\"$_\":" . js($d->{$_}) } sort keys %$d) . '}' }
  if (ref $d eq 'ARRAY') { return '[' . join(',', map { js($_) } @$d) . ']' }
  return 'null' unless defined $d;
  return $d if $d =~ /^-?(0|[1-9]\d{0,14})(\.\d+)?$/ && $d !~ /^0\d/;
  my $s = $d; $s =~ s/(["\\])/\\$1/g; $s =~ s/\n/\\n/g; $s =~ s/[\x00-\x1f]//g; return "\"$s\"";
}
sub idade { my ($d) = @_; return undef unless $d && $d =~ m{(\d\d)/(\d\d)/(\d{4})}; my $a = 2026 - $3; $a-- if ($2 > 10) || ($2 == 10 && $1 > 4); $a }

my %C; my @order; my %CPF;
my %want = map { $_ => 1 } ('PRESIDENTE','VICE-PRESIDENTE','GOVERNADOR','VICE-GOVERNADOR','SENADOR','1º SUPLENTE','2º SUPLENTE','DEPUTADO FEDERAL','DEPUTADO ESTADUAL');
for my $u ('BR', 'SP') {
  rd("consulta_cand_2026_$u.csv", sub {
    my $r = shift; return unless $want{$r->{DS_CARGO}};
    my $sq = $r->{SQ_CANDIDATO};
    $C{$sq} = {
      sq => $sq, cargo => $r->{DS_CARGO}, uf => $r->{SG_UF}, nr => $r->{NR_CANDIDATO},
      urna => $r->{NM_URNA_CANDIDATO}, nome => $r->{NM_CANDIDATO},
      sg => $r->{SG_PARTIDO}, pn => $r->{NM_PARTIDO}, fed => nul($r->{SG_FEDERACAO}),
      colig => ($r->{NM_COLIGACAO} =~ /PARTIDO ISOLADO|FEDERAÇÃO/ ? undef : $r->{NM_COLIGACAO}),
      comp => nul($r->{DS_COMPOSICAO_COLIGACAO}),
      gen => $r->{DS_GENERO}, cor => $r->{DS_COR_RACA}, esc => $r->{DS_GRAU_INSTRUCAO},
      civ => $r->{DS_ESTADO_CIVIL}, ocu => $r->{DS_OCUPACAO}, nasc => $r->{DT_NASCIMENTO},
      id => idade($r->{DT_NASCIMENTO}), ufn => nul($r->{SG_UF_NASCIMENTO}),
    };
    push @order, $sq;
    $CPF{$r->{NR_CPF_CANDIDATO}} = $sq if $r->{NR_CPF_CANDIDATO} =~ /^\d{11}$/;
  });
  rd("consulta_cand_complementar_2026_$u.csv", sub {
    my $r = shift; my $c = $C{$r->{SQ_CANDIDATO}} or return;
    $c->{sit} = nul($r->{DS_SITUACAO_CANDIDATO_TOT});
    $c->{jul} = nul($r->{DS_SITUACAO_JULGAMENTO});
    $c->{urnaSim} = $r->{ST_CANDIDATO_INSERIDO_URNA} eq 'SIM' ? 1 : 0;
    $c->{dest} = nul($r->{NM_TIPO_DESTINACAO_VOTOS});
    $c->{subst} = $r->{ST_SUBSTITUIDO} eq 'S' ? 1 : 0;
    $c->{mun} = nul($r->{NM_MUNICIPIO_NASCIMENTO});
    $c->{tetoGasto} = num($r->{VR_DESPESA_MAX_CAMPANHA}) || undef;
    $c->{quil} = $r->{ST_QUILOMBOLA} eq 'S' ? 1 : undef;
    $c->{ind} = nul($r->{DS_ETNIA_INDIGENA}); $c->{ind} = undef if ($c->{ind} // '') =~ /NÃO/;
  });
  rd("bem_candidato_2026_$u.csv", sub {
    my $r = shift; my $c = $C{$r->{SQ_CANDIDATO}} or return;
    my $v = num($r->{VR_BEM_CANDIDATO});
    $c->{bens} += $v; $c->{nb}++;
    my $t = $r->{DS_TIPO_BEM_CANDIDATO};
    my $cat = $t =~ /Casa|Apartamento|Terreno|Prédio|Sala|Loja|Galpão|imóve|Imóve|rural|Terra nua|Construção|Benfeitoria/i ? 'Imóveis'
            : $t =~ /Veículo|automotor|Embarca|Aeronave/i ? 'Veículos'
            : $t =~ /Quotas|Ações|capital|Participaç/i ? 'Participações societárias'
            : $t =~ /Depósito|Poupança|poupança|renda fixa|Fundo|fundos|Aplicação|aplicação|Títulos|Criptoativo|conta corrente|Dinheiro|espécie|Previdência|VGBL|PGBL|Ouro/i ? 'Aplicações e dinheiro'
            : 'Outros';
    $c->{bc}{$cat} += $v;
    push @{$c->{bl}}, [$t, $r->{DS_BEM_CANDIDATO}, $v];
  });
}

# histórico
my %need;
rd('historico_candidatura_2026_BRASIL.csv', sub {
  my $r = shift; my $c = $C{$r->{SQ_CANDIDATO_ATUAL}} or return;
  return if $r->{ANO_ELEICAO} >= 2026;
  my $h = { a => $r->{ANO_ELEICAO}, t => $r->{NR_TURNO}, cg => $r->{DS_CARGO}, ue => $r->{NM_UE}, uf => $r->{SG_UF},
            p => $r->{SG_PARTIDO}, nr => $r->{NR_CANDIDATO}, sit => nul($r->{DS_SITUACAO_CANDIDATURA}),
            res => nul($r->{DS_SIT_TOT_TURNO}), sq => $r->{SQ_CANDIDATO} };
  push @{$c->{hist}}, $h;
  $need{$r->{SQ_CANDIDATO}} = 1;
});

# eleições anteriores a 2004 (o histórico do TSE começa em 2004)
sub normn { my $s = uc(shift // ''); $s =~ tr/ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ/AAAAAEEEEIIIIOOOOOUUUUCN/; $s =~ s/[^A-Z ]//g; $s =~ s/\s+/ /g; $s =~ s/^ | $//g; $s }
sub tcase { my $s = lc(shift // ''); $s =~ s/(^|[\s\/-])(\p{L})/$1\u$2/g; $s =~ s/\b(D[aeo]s?|E)\b/\l$1/g; $s }
my %resn = ('ELEITO' => 'Eleito', 'NÃO ELEITO' => 'Não eleito', 'SUPLENTE' => 'Suplente', '2º TURNO' => '2º turno',
            'ELEITO POR MÉDIA' => 'Eleito por média', 'MÉDIA' => 'Eleito por média', 'ELEITO POR QP' => 'Eleito por QP');
sub resn { my $v = nul(shift); return undef unless defined $v; $resn{uc $v} // $resn{$v} // ($v =~ /[a-z]/ ? $v : ucfirst(lc $v)) }
sub rd_raw { my ($f, $cb) = @_; open my $h, "<:encoding(latin1)", $f or die "$f: $!"; while (my $l = <$h>) { $l =~ s/\r?\n$//; $cb->(map { s/^"|"$//gr } split /;/, $l, -1) } }
my (%byND, %byN);
for my $c (values %C) { my $n = normn($c->{nome}); $byND{"$n|$c->{nasc}"} = $c; push @{$byN{$n}}, $c }
my %oldh;   # sq antigo => [candidato, linha]
for my $y (1994, 1996, 1998, 2000, 2002) {
  print STDERR "candidatos $y\n";
  rd("old/hist/consulta_cand_${y}_BRASIL.csv", sub {
    my $r = shift;
    my $cpf = $r->{NR_CPF_CANDIDATO} // '';
    my $c = ($cpf =~ /^\d{11}$/ && $CPF{$cpf}) ? $C{$CPF{$cpf}} : $byND{ normn($r->{NM_CANDIDATO}) . '|' . ($r->{DT_NASCIMENTO} // '') } or return;
    my $sit = nul($r->{DS_SITUACAO_CANDIDATURA}); $sit = nul($r->{DS_DETALHE_SITUACAO_CAND}) if !defined $sit || $sit eq 'APTO' && nul($r->{DS_DETALHE_SITUACAO_CAND});
    my $h = { a => $y, t => $r->{NR_TURNO}, cg => tcase($r->{DS_CARGO}), ue => $r->{NM_UE}, uf => $r->{SG_UF},
              p => $r->{SG_PARTIDO}, nr => $r->{NR_CANDIDATO}, sit => $sit ? ucfirst(lc $sit) : undef,
              res => resn($r->{DS_SIT_TOT_TURNO}), sq => "$y-$r->{SQ_CANDIDATO}" };
    push @{$c->{hist}}, $h;
  });
}
# 1982–1990: só há votação por UF, sem CPF nem nascimento. Vínculo por nome completo idêntico,
# único entre os candidatos de 2026, com idade mínima e UF coerente com o resto da trajetória.
# deputados federais da Câmara (nome civil + nascimento + legislaturas) confirmam mandatos anteriores a 1994
my %camL;
{ open my $h, '<:encoding(UTF-8)', 'leg/cam/deputados.csv' or die; <$h>;
  while (my $l = <$h>) { $l =~ s/\r?\n$//; my @x = map { s/^"|"$//gr } split /";"/, $l, -1;
    my ($y, $m, $d) = split /-/, $x[9] // ''; next unless $d; $camL{ normn($x[4]) . "|$d/$m/$y" } = [$x[2], $x[3]] } }
for my $y (1982, 1986, 1989, 1990) {
  my ($d) = grep { -d } glob("old/hist/VOTACAO_CANDIDATO*_$y");
  my %agg;
  for my $f (glob("$d/*.txt")) {
    rd_raw($f, sub {
      my @x = @_;
      my $k = join '|', $x[3], $x[6], $x[12], normn($x[10]);
      my $g = $agg{$k} //= { t => $x[3], ue => $x[6], cg => $x[12], nome => $x[10], p => $x[20], nr => $x[8], sit => nul($x[16]), res => nul($x[18]), v => 0 };
      $g->{v} += $x[-1] =~ /^\d+$/ ? $x[-1] : 0;
    });
  }
  # 2º turno sem resultado: mais votado na disputa é o eleito
  my %disp; push @{ $disp{"$_->{t}|$_->{ue}|$_->{cg}"} }, $_ for values %agg;
  for my $l (values %disp) { next unless $l->[0]{t} == 2 && !grep { defined $_->{res} } @$l; my @s = sort { $b->{v} <=> $a->{v} } @$l; $s[0]{res} = 'ELEITO'; $_->{res} = 'NÃO ELEITO' for @s[1..$#s] }
  my %seen; $seen{ normn($_->{nome}) }{"$_->{ue}|$_->{cg}"} = 1 for values %agg;
  for my $g (values %agg) {
    my $n = normn($g->{nome}); my $cs = $byN{$n} or next;
    next if @$cs != 1 || (split / /, $n) < 3 || keys %{ $seen{$n} } > 1;
    my $c = $cs->[0];
    next unless $c->{nasc} =~ m{(\d{4})$} && $1 <= $y - 18;
    my %ufs = map { $_ => 1 } grep { $_ } $c->{uf}, $c->{ufn}, map { $_->{uf} } @{ $c->{hist} // [] };
    my $sig = grep { !/^(DA|DE|DO|DAS|DOS|E)$/ } split / /, $n;
    my $car = grep { ($_->{uf} // '') eq $g->{ue} && ($_->{p} // '') eq $g->{p} } @{ $c->{hist} // [] };
    my $cam = $camL{"$n|$c->{nasc}"}; my $leg = 49 + ($y - 1990) / 4;
    my $conf = $g->{cg} eq 'DEPUTADO FEDERAL' && $cam && $cam->[0] <= $leg && $leg <= $cam->[1];
    next unless $g->{ue} eq 'BR' || $conf || ($c->{cargo} =~ /PRESIDENTE/ && $sig >= 4)
             || ($ufs{ $g->{ue} } && ($sig >= 4 || ($sig == 3 && $car)));
    push @{$c->{hist}}, { a => $y, t => $g->{t}, cg => tcase($g->{cg}), ue => ($g->{ue} eq 'BR' ? 'BRASIL' : $g->{ue}), uf => $g->{ue},
                          p => $g->{p}, nr => $g->{nr}, sit => $g->{sit} ? ucfirst(lc $g->{sit}) : undef, res => resn($g->{res}), sq => "$y-$n" };
    print STDERR "  $y $c->{urna} ($c->{cargo}) <- $g->{nome} $g->{cg} $g->{ue} T$g->{t} " . ($g->{res} // '-') . "\n";
  }
}
# 2004–2016: linhas sem resultado no histórico do TSE; completa pela votação oficial
my %fill; my %mj = map { $_ => 1 } qw(Presidente Governador Senador Prefeito);
for my $c (values %C) { for my $h (@{ $c->{hist} // [] }) { push @{ $fill{$h->{a}}{$h->{sq}} }, $h if !defined $h->{res} && ($h->{sit} // '') eq 'Apto' && $h->{a} >= 2004 } }
for my $y (sort keys %fill) {
  my $f = "old/hist/votacao_candidato_munzona_${y}_BRASIL.csv"; next unless -e $f;
  print STDERR "votação $y\n";
  my (%res, %vot, %cont);
  open my $fh, "<:encoding(latin1)", $f or die; my $hd = <$fh>; $hd =~ s/\r?\n$//; my @hd = map { s/"//gr } split /;/, $hd; my %ix; @ix{@hd} = 0 .. $#hd;
  while (my $l = <$fh>) {
    my @x = map { s/"//gr } split /;/, $l;
    my $t = $x[$ix{NR_TURNO}]; next unless $t == 2 || $fill{$y}{ $x[$ix{SQ_CANDIDATO}] };
    my $sq = $x[$ix{SQ_CANDIDATO}]; my $ck = "$t|$x[$ix{SG_UE}]|$x[$ix{CD_CARGO}]";
    $res{"$sq|$t"} //= nul($x[$ix{DS_SIT_TOT_TURNO}]);
    if ($t == 2) { $vot{$ck}{$sq} += $x[$ix{QT_VOTOS_NOMINAIS}]; $cont{"$sq|2"} = $ck }
  }
  close $fh;
  for my $sq (keys %{ $fill{$y} }) {
    for my $h (@{ $fill{$y}{$sq} }) {
      my $r = $res{"$sq|$h->{t}"};
      if (!defined $r && $h->{t} == 2 && $mj{$h->{cg}} && (my $ck = $cont{"$sq|2"})) {
        my ($top) = sort { $vot{$ck}{$b} <=> $vot{$ck}{$a} } keys %{ $vot{$ck} };
        $r = $top eq $sq ? 'ELEITO' : 'NÃO ELEITO';
      }
      $h->{res} = resn($r) if defined $r;
    }
  }
}
# nome do estado por extenso nas disputas estaduais (arquivos antigos trazem sigla ou nome sem acento)
my %UFN = (AC=>'ACRE',AL=>'ALAGOAS',AM=>'AMAZONAS',AP=>'AMAPÁ',BA=>'BAHIA',CE=>'CEARÁ',DF=>'DISTRITO FEDERAL',ES=>'ESPÍRITO SANTO',GO=>'GOIÁS',MA=>'MARANHÃO',MG=>'MINAS GERAIS',MS=>'MATO GROSSO DO SUL',MT=>'MATO GROSSO',PA=>'PARÁ',PB=>'PARAÍBA',PE=>'PERNAMBUCO',PI=>'PIAUÍ',PR=>'PARANÁ',RJ=>'RIO DE JANEIRO',RN=>'RIO GRANDE DO NORTE',RO=>'RONDÔNIA',RR=>'RORAIMA',RS=>'RIO GRANDE DO SUL',SC=>'SANTA CATARINA',SE=>'SERGIPE',SP=>'SÃO PAULO',TO=>'TOCANTINS',BR=>'BRASIL');
for my $c (values %C) { for my $h (@{ $c->{hist} // [] }) { $h->{ue} = $UFN{$h->{uf}} if $UFN{$h->{uf} // ''} && $h->{cg} !~ /Prefeito|Vereador/i } }
# dedup turnos: keep one row per (ano, cargo, sq), preferring o último turno com resultado
for my $c (values %C) {
  next unless $c->{hist};
  my %k;
  for my $h (sort { (defined $a->{res}) <=> (defined $b->{res}) || $a->{t} <=> $b->{t} } @{$c->{hist}}) { $k{"$h->{a}|$h->{sq}"} = $h }
  $c->{hist} = [ sort { $b->{a} <=> $a->{a} } values %k ];
}
# bens antigos
my %oldb;
for my $y (2014, 2016, 2018, 2020, 2022, 2024) {
  print STDERR "bens $y\n";
  rd("old/bem_candidato_${y}_BRASIL.csv", sub { my $r = shift; return unless $need{$r->{SQ_CANDIDATO}}; $oldb{$r->{SQ_CANDIDATO}} += num($r->{VR_BEM_CANDIDATO}); });
}
for my $c (values %C) {
  next unless $c->{hist};
  for my $h (@{$c->{hist}}) { $h->{b} = $oldb{$h->{sq}} if exists $oldb{$h->{sq}}; delete $h->{sq}; delete $h->{t} }
  my @h = @{$c->{hist}};
  $c->{nh} = scalar @h;
  $c->{ne} = scalar grep { ($_->{res} // '') =~ /^ELEITO|^Eleito|MÉDIA|QP|Média/ && $_->{res} !~ /Não eleito|NÃO ELEITO/i } @h;
  # mandato atual: eleito em 2022 (geral) ou 2024 (municipal)
  my ($m) = grep { $_->{a} >= 2022 && ($_->{res} // '') =~ /eleito|média|qp/i && $_->{res} !~ /não eleito|suplente/i } @h;
  $c->{mand} = $m ? "$m->{cg} ($m->{a}" . ($m->{a} == 2024 ? ", $m->{ue}" : '') . ")" : undef;
}

# só detalha lista de bens para majoritários; deputados ficam com totais por categoria
for my $c (values %C) {
  $c->{bens} = sprintf('%.2f', $c->{bens}) + 0 if defined $c->{bens};
  $c->{bc}{$_} = sprintf('%.2f', $c->{bc}{$_}) + 0 for keys %{ $c->{bc} // {} };
  if ($c->{cargo} =~ /DEPUTADO/) { delete $c->{bl} } else { $c->{bl} = [ sort { $b->[2] <=> $a->[2] } @{ $c->{bl} // [] } ] }
  $c->{foto} = 1 if -e "fotos/F$c->{uf}$c->{sq}_div.jpg";
}
print 'window.TSE=' . js([ map { $C{$_} } @order ]) . ";\n";
