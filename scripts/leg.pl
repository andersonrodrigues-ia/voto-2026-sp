#!/usr/bin/perl
# Atuação no poder público: autoria de proposições (Câmara 2003-2026, Senado, Alesp) e proposições do Executivo
use strict; use warnings; use utf8; use JSON::PP; use Unicode::Normalize;
binmode STDOUT, ':utf8'; binmode STDERR, ':utf8';

sub norm { my $s = NFD(lc(shift // '')); $s =~ s/\pM//g; $s =~ s/[^a-z ]/ /g; $s =~ s/\s+/ /g; $s =~ s/^ | $//g; $s }
sub trim { my ($s, $n) = @_; $s //= ''; $s =~ s/\s+/ /g; $s =~ s/^\s+|\s+$//g; length($s) > $n ? substr($s, 0, $n - 1) . '…' : $s }
sub rdcsv {   # CSV ; com aspas e quebras de linha; $pre recebe a linha crua para filtro rápido
  my ($f, $cb, $pre) = @_; open my $h, '<:encoding(UTF-8)', $f or do { warn "$f: $!"; return }; my @h;
  while (my $l = <$h>) {
    while ((($l =~ tr/"//) % 2) && !eof($h)) { $l =~ s/\r?\n$/ /; $l .= <$h> }
    $l =~ s/\r?\n$//; $l =~ s/^\x{feff}//;
    if (@h && $pre && !$pre->($l)) { next }
    my @x; while ($l =~ /\G(?:"((?:[^"]|"")*)"|([^;]*))(?:;|$)/g) { push @x, defined $1 ? $1 =~ s/""/"/gr : $2; last if pos($l) >= length $l }
    if (!@h) { @h = @x; next } my %r; @r{@h} = @x; $cb->(\%r);
  }
}
my $D = '..';
# ---------- candidatos ----------
my $cands; { local $/; open my $h, '<:utf8', "$D/data.js" or die; my $j = <$h>; $j =~ s/^window\.TSE=//; $j =~ s/;\s*$//; $cands = JSON::PP->new->decode($j) }
my %want = map { $_ => 1 } ('PRESIDENTE','VICE-PRESIDENTE','GOVERNADOR','VICE-GOVERNADOR','SENADOR','1º SUPLENTE','2º SUPLENTE','DEPUTADO FEDERAL','DEPUTADO ESTADUAL');
my @C = grep { $want{$_->{cargo}} } @$cands;
my %OUT;

# ---------- CÂMARA ----------
my %camKey;   # nome civil + nascimento -> id
rdcsv("cam/deputados.csv", sub { my $r = shift; my ($id) = $r->{uri} =~ /(\d+)$/; $camKey{ norm($r->{nomeCivil}) . '|' . $r->{dataNascimento} } = [$id, $r->{nome}, $r->{idLegislaturaInicial}, $r->{idLegislaturaFinal}] });
my (%camOf, %sqOfCam);
for my $c (@C) { next unless $c->{nasc} && $c->{nasc} =~ m{(\d\d)/(\d\d)/(\d{4})}; my $k = norm($c->{nome}) . "|$3-$2-$1"; if (my $m = $camKey{$k}) { $camOf{$c->{sq}} = $m; $sqOfCam{$m->[0]} = $c->{sq} } }
print STDERR "Câmara: ", scalar(keys %camOf), " candidatos com passagem pela Câmara\n";
my (%pa, %execProp);   # idProp -> [[sq, principal]]
for my $y (2003 .. 2026) {
  rdcsv("cam/aut-$y.csv", sub { my $r = shift;
    if ($r->{idDeputadoAutor} && $sqOfCam{$r->{idDeputadoAutor}}) { push @{$pa{$r->{idProposicao}}}, [$sqOfCam{$r->{idDeputadoAutor}}, ($r->{ordemAssinatura} eq '1' || $r->{proponente} eq '1' && $r->{ordemAssinatura} eq '1') ? 1 : 0] }
    elsif ($r->{nomeAutor} eq 'Poder Executivo') { $execProp{$r->{idProposicao}} = 1 } });
}
my (%camItems, %execItems);
my %MAIN = map { $_ => 1 } qw(PL PLP PEC PDL MPV PLV);
for my $y (2003 .. 2026) {
  rdcsv("cam/prop-$y.csv", sub { my $r = shift; my $id = $r->{id};
      my $it = { t => $r->{siglaTipo}, n => $r->{numero}, a => $r->{ano}, e => trim($r->{ementa}, 260), d => substr($r->{dataApresentacao}, 0, 10), s => $r->{ultimoStatus_descricaoSituacao}, id => $id };
      if ($pa{$id}) { for my $p (@{$pa{$id}}) { push @{$camItems{$p->[0]}}, { %$it, pr => $p->[1] } } }
      if ($execProp{$id}) { push @{$execItems{camara}}, $it } },
    sub { my $l = shift; my ($id) = $l =~ /^\x{feff}?"(\d+)"/; $id && ($pa{$id} || $execProp{$id}) });
}
sub isLaw { ($_[0] // '') =~ /Transformad[oa] em Norma Jur|Transformad[oa] em Lei/i }
# lei "simbolica": nome de via/predio, utilidade publica, data comemorativa, titulo, "capital de"
sub isSimb { ($_[0] // '') =~ /^\s*(D. (a )?denomina|Denomina|Declara (de )?utilidade p|Institui (o|a) .?(Dia|Semana|M.s|Ano) |Inclui .{0,80}Calend.rio|Confere (o )?t.tulo|Concede (o )?t.tulo|Declara (o|a) Munic.pio .{0,80}Capital|Declara .{0,80}Capital (Nacional|Paulista|Estadual)|Reconhece .{0,120}(Capital|patrim.nio cultural)|Declara como Capital|Altera a denomina|Inscreve o nome|Institui (o|a) .{0,40}(Dia|Semana) )/i }
sub camSummary {
  my ($items) = @_; my %cnt; my (@laws, @recent, %seen);
  for my $i (@$items) { next if $seen{$i->{id}}++; my $k = $MAIN{$i->{t}} ? $i->{t} : ($i->{t} =~ /^(REQ|RIC|INC|RCP)$/ ? 'REQ' : 'OUT');
    $cnt{"$k:" . ($i->{pr} ? 'p' : 'c')}++;
    if ($MAIN{$i->{t}}) { if (isLaw($i->{s})) { $cnt{'lei:' . ($i->{pr} ? 'p' : 'c')}++; $cnt{'leiS:' . ($i->{pr} ? 'p' : 'c')}++ if isSimb($i->{e}); $i->{simb} = 1 if isSimb($i->{e}); push @laws, $i } elsif ($i->{s} =~ /Aguardando Aprecia\S* pelo Senado|Remetida ao Senado|Aguardando Sanç/i) { $cnt{'aprov:' . ($i->{pr} ? 'p' : 'c')}++ } }
    push @recent, $i if $i->{pr} && $MAIN{$i->{t}} && !isLaw($i->{s}); }
  @laws = sort { ($b->{pr} <=> $a->{pr}) || (($a->{simb} // 0) <=> ($b->{simb} // 0)) || ($b->{d} cmp $a->{d}) } @laws;
  @recent = (sort { $b->{d} cmp $a->{d} } @recent)[0 .. 11]; @recent = grep { defined } @recent;
  my @years = sort map { substr($_->{d}, 0, 4) } grep { $_->{d} } @$items;
  return { cnt => \%cnt, laws => [ @laws[0 .. ($#laws < 29 ? $#laws : 29)] ], recent => \@recent, de => $years[0], ate => $years[-1] };
}
for my $sq (keys %camItems) { my $s = camSummary($camItems{$sq}); $s->{casa} = 'Câmara dos Deputados'; $s->{nomeCasa} = $camOf{$sq}[1]; $s->{link} = "https://www.camara.leg.br/deputados/$camOf{$sq}[0]"; push @{$OUT{$sq}}, $s }

# ---------- SENADO ----------
my %SEN = (5894 => 'FLAVIO NANTES BOLSONARO', 456 => 'RONALDO RAMOS CAIADO', 5527 => 'SIMONE NASSAR TEBET ROCHA', 59 => 'MARIA OSMARINA MARINA DA SILVA VAZ DE LIMA', 5976 => 'LUIS EDUARDO GRANGEIRO GIRAO');
for my $cod (sort keys %SEN) {
  my @sqs = map { $_->{sq} } grep { norm($_->{nome}) eq norm($SEN{$cod}) } @C; unless (@sqs) { warn "Senado $cod sem candidato\n"; next }
  my ($aut, $proc); { local $/; open my $h, '<', "sen/aut-$cod.json"; $aut = decode_json(<$h>); open $h, '<', "sen/proc-$cod.json"; $proc = decode_json(<$h>) }
  my %princ; my $A = $aut->{MateriasAutoriaParlamentar}{Parlamentar}{Autorias}{Autoria} // []; $A = [$A] if ref $A eq 'HASH';
  for my $a (@$A) { $princ{$a->{Materia}{Codigo}} = ($a->{IndicadorAutorPrincipal} // '') eq 'Sim' ? 1 : 0 }
  my @items;
  for my $p (@$proc) { my ($t, $n, $yy) = ($p->{identificacao} // '') =~ /^(\S+) (\d+)\/(\d+)/ or next;
    $t = 'PL' if $t eq 'PLS'; $t = 'PLP' if $t eq 'PLS-C' || $t eq 'PLC' && 0; my $pr = $princ{$p->{codigoMateria}} // 0;
    push @items, { t => $t, n => $n, a => $yy, e => trim($p->{ementa}, 260), d => $p->{dataApresentacao}, s => ($p->{normaGerada} ? "Transformado em Norma Jurídica ($p->{normaGerada})" : ($p->{situacaoAtual} // ($p->{tramitando} eq 'Sim' ? 'Em tramitação' : 'Encerrada'))), id => $p->{codigoMateria}, pr => $pr, sen => 1 } }
  my $s = camSummary(\@items); $s->{casa} = 'Senado Federal'; $s->{link} = "https://www25.senado.leg.br/web/senadores/senador/-/perfil/$cod"; $s->{sen} = 1;
  push @{$OUT{$_}}, $s for @sqs;
}

# ---------- ALESP ----------
my %natSg = (1 => 'PL', 2 => 'PLC', 3 => 'PR', 4 => 'PDL', 5 => 'PEC', 6 => 'MOC', 7 => 'REQ', 8 => 'RI', 9 => 'IND');
my (%docAut, %autName);
{ open my $h, '<:utf8', 'alesp/documento_autor.xml' or die; local $/ = '</DocumentoAutor>';
  while (my $r = <$h>) { my ($ia) = $r =~ /<IdAutor>(\d+)/; my ($id) = $r =~ /<IdDocumento>(\d+)/; my ($nm) = $r =~ /<NomeAutor>([^<]*)/; next unless $id; push @{$docAut{$id}}, $ia; $autName{$ia} = $nm } }
# candidatos com passagem pela Alesp (histórico TSE) ou ocupação de deputado; casa pelo nome
my %autCount; $autCount{$_}++ for map { @$_ } values %docAut;
my %autYears;   # autor -> ano -> nº de proposituras (para a prova de tempo)
{ open my $h, '<:utf8', 'alesp/proposituras.xml' or die; local $/ = '</propositura>';
  while (my $r = <$h>) { my ($id) = $r =~ /<IdDocumento>(\d+)/ or next; my ($y) = $r =~ /<DtPublicacao>(\d{4})/ or next; $autYears{$_}{$y}++ for @{ $docAut{$id} // [] } } }
my (%sqOfAut, %cand);
for my $c (@C) {
  my @terms = map { $_->{a} } grep { $_->{cg} =~ /Deputado Estadual/i && ($_->{uf} // '') eq 'SP' } @{ $c->{hist} // [] };
  next unless $c->{uf} eq 'SP' && @terms;
  my %inTerm; for my $y (@terms) { $inTerm{$_} = 1 for $y + 1 .. $y + 4 }
  my $TIT = qr/^(dr|dra|pr|pastor|pastora|delegado|delegada|tenente|coronel|major|sargento|cabo|capitao|agente federal|agente|professor|professora|prof|vereador|vereadora|missionario|bispo|irma|irmao)\s+/;
  my %tok = map { $_ => 1 } split / /, norm($c->{nome}); (my $u = norm($c->{urna})) =~ s/$TIT//; my %utok = map { $_ => 1 } grep { length > 2 } split / /, $u;
  my @hit;
  for my $id (grep { ($autCount{$_} // 0) >= 5 } keys %autName) {
    (my $a = norm($autName{$id})) =~ s/$TIT//; next if $a =~ /^(governador|mesa|comissao|lideranca|bancada)/;
    my @at = grep { length > 2 && !/^(dos|das|del)$/ } split / /, $a;
    my $nameOk = $a eq $u || $a eq norm($c->{nome})
      || (@at >= 2 && !grep { !$tok{$_} } @at)                                   # autor contido no nome civil
      || (keys %utok >= 2 && !grep { my $t = $_; !grep { $_ eq $t } @at } keys %utok);   # nome de urna contido no nome do autor
    next unless $nameOk;
    # prova de tempo: a maior parte dos documentos do autor cai dentro dos mandatos do candidato
    # (só anos a partir de 2003: o histórico do TSE começa em 2004)
    my $ys = $autYears{$id} // {}; my ($tot, $in) = (0, 0); for my $y (grep { $_ >= 2003 } keys %$ys) { $tot += $ys->{$y}; $in += $ys->{$y} if $inTerm{$y} }
    my $ratio = $tot ? $in / $tot : 0;
    my $exact = ($a eq $u || $a eq norm($c->{nome}));
    if (($ratio >= 0.6 || $exact && $ratio >= 0.4) && $tot >= 3) {
      my $sc = ($a eq $u || $a eq norm($c->{nome})) ? 3 : (@at >= 2 && !grep { !$tok{$_} } @at) ? 2 : 1;
      push @{$cand{$id}}, [$c->{sq}, $sc, $c->{urna}, $c->{urnaSim} ? 1 : 0]; push @hit, $id;
    } else { printf STDERR "Alesp (descartado, %.0f%% de %d docs no mandato): %s <- %s\n", 100 * $ratio, $tot, $c->{urna}, $autName{$id} }
  }
  print STDERR "Alesp: $c->{urna} <- ", join(' | ', map { $autName{$_} } @hit), "\n" if @hit;
}
# um autor, um candidato: vence o vínculo mais forte; empate = descarta
for my $id (keys %cand) {
  my @l = sort { $b->[1] <=> $a->[1] || $b->[3] <=> $a->[3] } @{$cand{$id}};
  if (@l > 1 && $l[0][1] == $l[1][1] && $l[0][3] == $l[1][3]) { print STDERR "Alesp (ambíguo, descartado): $autName{$id} -> ", join(', ', map { $_->[2] } @l), "\n"; next }
  print STDERR "Alesp (resolvido): $autName{$id} -> $l[0][2] (não ", join(', ', map { $_->[2] } @l[1 .. $#l]), ")\n" if @l > 1;
  $sqOfAut{$id} = $l[0][0];
}
my ($govId) = grep { $autName{$_} eq 'Governador' } keys %autName;
my (%needDoc, %ad);
for my $id (keys %docAut) { for my $a (@{$docAut{$id}}) { if ($sqOfAut{$a}) { $needDoc{$id} = 1; push @{$ad{$id}}, [$sqOfAut{$a}, $a == $docAut{$id}[0] ? 1 : 0] } if (defined $govId && $a == $govId) { $needDoc{$id} = 1; push @{$ad{$id}}, ['GOV', 1] } } }
my %prop;
{ open my $h, '<:utf8', 'alesp/proposituras.xml' or die; local $/ = '</propositura>';
  while (my $r = <$h>) { my ($id) = $r =~ /<IdDocumento>(\d+)/ or next; next unless $needDoc{$id}; my ($nat) = $r =~ /<IdNatureza>(\d+)/; my ($a) = $r =~ /<AnoLegislativo>(\d+)/; my ($n) = $r =~ /<NroLegislativo>(\d+)/; my ($e) = $r =~ /<Ementa>([^<]*)/; my ($d) = $r =~ /<DtPublicacao>(\d{4}-\d\d-\d\d)/;
    $prop{$id} = { t => $natSg{$nat // 0} // 'OUT', n => $n, a => $a, e => trim($e, 260), d => $d // '', id => $id } } }
my %flag;
{ open my $h, '<:raw', 'alesp/documento_andamento.xml' or die; local $/ = '</DocumentoAndamento>';
  while (my $r = <$h>) { next unless $r =~ /Publicad[oa] (?:a |o )?(?:Lei|Autógrafo|Aut\xC3\xB3grafo)|Veto Total|Promulgad/; my ($id) = $r =~ /<IdDocumento>(\d+)/; next unless $id && $prop{$id};
    my ($ds) = $r =~ /<Descricao>([^<]*)/; utf8::decode($ds);
    if ($ds =~ /Publicad[oa] (?:a )?Lei (?:Complementar )?(?:n[ºo°.]*\s*)?([\d.]+)/i) { $flag{$id}{lei} = $1 }
    elsif ($ds =~ /Autógrafo/) { $flag{$id}{aut} = 1 }
    elsif ($ds =~ /Veto Total/) { $flag{$id}{veto} = 1 } } }
my (%alItems, @govItems);
for my $id (keys %ad) { my $p = $prop{$id} or next; my $f = $flag{$id} // {};
  my $s = $f->{lei} ? "Transformado em Norma Jurídica (Lei $f->{lei})" : $f->{veto} ? 'Vetado pelo governador' : $f->{aut} ? 'Aprovado pela Alesp' : 'Sem aprovação registrada';
  for my $x (@{$ad{$id}}) { my $it = { %$p, s => $s, pr => $x->[1], al => 1 }; if ($x->[0] eq 'GOV') { push @govItems, $it } else { push @{$alItems{$x->[0]}}, $it } } }
%MAIN = map { $_ => 1 } qw(PL PLC PEC PDL PR);
sub alSummary { my $items = shift; my %cnt; my (@laws, @recent, %seen);
  for my $i (@$items) { next if $seen{$i->{id}}++; my $k = $MAIN{$i->{t}} ? $i->{t} : ($i->{t} =~ /^(REQ|RI)$/ ? 'REQ' : $i->{t}); $cnt{"$k:" . ($i->{pr} ? 'p' : 'c')}++;
    if ($MAIN{$i->{t}}) { if (isLaw($i->{s})) { $cnt{'lei:' . ($i->{pr} ? 'p' : 'c')}++; $cnt{'leiS:' . ($i->{pr} ? 'p' : 'c')}++ if isSimb($i->{e}); $i->{simb} = 1 if isSimb($i->{e}); push @laws, $i } elsif ($i->{s} =~ /^Aprovado/) { $cnt{'aprov:' . ($i->{pr} ? 'p' : 'c')}++ } elsif ($i->{s} =~ /^Vetado/) { $cnt{'veto:' . ($i->{pr} ? 'p' : 'c')}++ } }
    push @recent, $i if $i->{pr} && $MAIN{$i->{t}} && !isLaw($i->{s}); }
  @laws = sort { ($b->{pr} <=> $a->{pr}) || (($a->{simb} // 0) <=> ($b->{simb} // 0)) || ($b->{d} cmp $a->{d}) } @laws; @recent = grep { defined } (sort { $b->{d} cmp $a->{d} } @recent)[0 .. 11];
  my @years = sort map { substr($_->{d}, 0, 4) } grep { $_->{d} } @$items;
  { cnt => \%cnt, laws => [ @laws[0 .. ($#laws < 29 ? $#laws : 29)] ], recent => \@recent, de => $years[0], ate => $years[-1] } }
for my $sq (keys %alItems) { my $s = alSummary($alItems{$sq}); $s->{casa} = 'Assembleia Legislativa de SP'; $s->{link} = 'https://www.al.sp.gov.br/deputado/lista/'; push @{$OUT{$sq}}, $s }

# ---------- EXECUTIVO ----------
my %EXEC;
my ($lula) = grep { $_->{cargo} eq 'PRESIDENTE' && $_->{urna} eq 'LULA' } @C;
my ($tarc) = grep { $_->{cargo} eq 'GOVERNADOR' && $_->{urna} =~ /^TARC/ } @C;
sub execBlock { my ($items, $from, $to, $label, $fonte) = @_; my @i = grep { $_->{d} ge $from && $_->{d} le $to && $_->{t} =~ /^(MPV|PL|PLP|PEC|PLC)$/ } @$items;
  my %cnt; my @laws; for my $x (@i) { $cnt{$x->{t}}++; if (isLaw($x->{s})) { $cnt{lei}++; $cnt{"lei_$x->{t}"}++; push @laws, $x } }
  @laws = sort { $b->{d} cmp $a->{d} } @laws;
  { label => $label, de => $from, ate => $to, cnt => \%cnt, n => scalar @i, laws => [ @laws[0 .. ($#laws < 39 ? $#laws : 39)] ], fonte => $fonte } }
if ($lula) { $EXEC{$lula->{sq}} = [ execBlock($execItems{camara}, '2023-01-01', '2026-12-31', 'Governo atual (2023–2026)', 'Câmara dos Deputados, autoria "Poder Executivo"'),
                                     execBlock($execItems{camara}, '2003-01-01', '2010-12-31', 'Governos anteriores (2003–2010)', 'Câmara dos Deputados, autoria "Poder Executivo"') ] }
if ($tarc) { $EXEC{$tarc->{sq}} = [ execBlock(\@govItems, '2023-01-01', '2026-12-31', 'Governo atual (2023–2026)', 'Alesp, autoria "Governador"') ] }

# balanço autodeclarado nos planos (incumbentes do Executivo)
my $pt; { local $/; open my $h, '<:utf8', "$D/planos.js"; my $j = <$h>; ($pt) = $j =~ /window\.PTXT=(.*?);\nwindow/s; $pt = JSON::PP->new->decode($pt) }
my $MARK = qr/(nossa gestão|nosso governo|neste governo|nesta gestão|desde 2023|desde 2019|em nosso mandato|entregamos|inauguramos|já entregamos|foram entregues|foram entregu|foram inaugurad|foram criad|foram contratad|foram construíd|investimos R\$|retomamos|reduzimos|zeramos|alcançamos)/i;
my %BAL;
for my $c (grep { $_->{cargo} =~ /^(PRESIDENTE|GOVERNADOR)$/ && ($_->{mand} // '') =~ /^(Presidente|Governador)/ } @C) {
  my $s = $pt->{$c->{sq}} or next; my %seen;
  my @b = grep { length($_) >= 60 && length($_) <= 420 && !$seen{lc substr($_, 0, 50)}++ } grep { $_ =~ $MARK } @$s;
  next if @b < 3;   # poucas frases = provável falso positivo, não um balanço de gestão
  my @num = grep { /\d/ } @b; my @rest = grep { !/\d/ } @b;
  $BAL{$c->{sq}} = { n => scalar @b, q => [ (@num, @rest)[0 .. (@b < 40 ? $#b : 39)] ] };
}
my $json = JSON::PP->new->canonical;
print 'window.LEG=' . $json->encode(\%OUT) . ";\n";
print 'window.EXEC=' . $json->encode(\%EXEC) . ";\n";
print 'window.BAL=' . $json->encode(\%BAL) . ";\n";
printf STDERR "Saída: %d candidatos com atuação legislativa; executivo=%d; balanço=%d\n", scalar(keys %OUT), scalar(keys %EXEC), scalar(keys %BAL);
