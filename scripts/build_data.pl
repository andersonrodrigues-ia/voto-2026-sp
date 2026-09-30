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

my %C; my @order;
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
# dedup turnos: keep one row per (ano, cargo, sq), preferring último turno
for my $c (values %C) {
  next unless $c->{hist};
  my %k;
  for my $h (sort { $a->{t} <=> $b->{t} } @{$c->{hist}}) { $k{"$h->{a}|$h->{sq}"} = $h }
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
