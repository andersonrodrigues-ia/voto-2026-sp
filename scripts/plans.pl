#!/usr/bin/perl
# Análise textual dos planos de governo: páginas, palavras, cobertura por tema, concretude e trechos literais
use strict; use warnings; use utf8;
binmode STDOUT, ':utf8';

# cada tema: lista de radicais; o regex final exige início e fim de palavra
my @T = (
  ['eco', 'Economia e emprego',            'economi\w*|emprego\w*|desemprego|PIB|infla[çc][ãa]o|juros|industri\w*|investimentos? privados?|empreended\w*|empreendedorismo'],
  ['fis', 'Impostos e contas públicas',    'impost\w*|tribut\w*|fisca(?:l|is)|d[ée]ficit (?:prim[áa]rio|fiscal|p[úu]blico|nominal)|d[íi]vida p[úu]blica|gastos? p[úu]blicos?|or[çc]ament\w*|arcabou[çc]o'],
  ['sau', 'Saúde',                         'sa[úu]de|SUS|hospita\w*|m[ée]dic[oa]s?|vacina\w*|UBS|cirurgias?|medicamentos?'],
  ['edu', 'Educação',                      'educa[çc]\w*|escolas?|escolar\w*|ensino|professor\w*|universidades?|alfabetiza\w*|creches?|alunos?|estudantes?'],
  ['seg', 'Segurança pública',             'seguran[çc]a p[úu]blica|pol[íi]cia\w*|crimes?|criminal\w*|crime organizado|viol[êe]ncia|fac[çc][ãa]o|fac[çc][õo]es|pres[íi]dios?|penitenci\w*|tr[áa]fico|homic[íi]dios?'],
  ['amb', 'Meio ambiente e clima',         'meio ambiente|ambient\w*|clim[áa]tic\w*|clima|desmatamento|sustent[áa]ve(?:l|is)|sustentabilidade|Amaz[ôo]nia|renov[áa]ve(?:l|is)|carbono|transi[çc][ãa]o energ[ée]tica'],
  ['inf', 'Infraestrutura e mobilidade',   'infraestrutura|rodovi\w*|ferrovi\w*|transportes?|mobilidade|saneamento|metr[ôo]|portos?|aeroportos?|log[íi]stic\w*'],
  ['soc', 'Assistência e pobreza',         'pobreza|fome|Bolsa Fam[íi]lia|assist[êe]ncia social|vulner[áa]ve(?:l|is)|vulnerabilidade|desigualdades?|renda b[áa]sica|transfer[êe]ncia de renda|mis[ée]ria'],
  ['mor', 'Moradia',                       'moradias?|habita[çc]\w*|Minha Casa|casa pr[óo]pria|d[ée]ficit habitacional|aluguel'],
  ['tra', 'Trabalho e previdência',        'trabalhador\w*|previd[êe]nci\w*|aposentad\w*|CLT|sindica\w*|sal[áa]rio m[íi]nimo|jornada|6x1'],
  ['agr', 'Agro e campo',                  'agro\w*|agricult\w*|agropecu\w*|rura(?:l|is)|reforma agr[áa]ria'],
  ['est', 'Gestão, Estado e corrupção',    'corrup[çc]\w*|transpar[êe]ncia|efici[êe]ncia|privatiza\w*|estata(?:l|is)|desburocratiz\w*|reforma administrativa|gest[ãa]o p[úu]blica|servidor(?:es)? p[úu]blicos?|concess[ãaõo]\w*'],
  ['dir', 'Direitos e diversidade',        'mulher(?:es)?|feminic[íi]dio|negr[oa]s|racis\w*|raciais|racial|LGBT\w*|ind[íi]genas?|quilombolas?|pessoas? com defici[êe]ncia|igualdade de g[êe]nero|direitos humanos'],
  ['tec', 'Ciência, tecnologia e inovação','tecnolog\w*|inova[çc]\w*|digita(?:l|is)|digitaliza\w*|intelig[êe]ncia artificial|ci[êe]ncias?|pesquisas?|startups?|conectividade'],
  ['fam', 'Família e valores',             '(?<!Bolsa )fam[íi]lias?(?! e comunidade)|crist[ãa]os?|crist[ãa]s?|religi\w*|liberdade de express[ãa]o|liberdade religiosa|conservador\w*|aborto|ideologia de g[êe]nero'],
  ['ext', 'Soberania e relações externas', 'soberania|pol[íi]tica externa|rela[çc][õo]es internacionais|com[ée]rcio exterior|exporta[çc]\w*|Mercosul|BRICS|Estados Unidos|imperialis\w*|diplomac\w*'],
);
$_->[2] = qr/(?<!\w)(?:$_->[2])(?!\w)/i for @T;

my $VERB = qr/(?<!\w)(criar|criaremos|criação|ampliar|ampliaremos|ampliação|implantar|implementar|reduzir|reduziremos|redução|garantir|garantiremos|investir|investiremos|zerar|acabar|extinguir|privatizar|construir|construiremos|contratar|isentar|isenção|aumentar|expandir|universalizar|estatizar|revogar|instituir|triplicar|dobrar|eliminar|combater|fortalecer|retomar|modernizar|federalizar|endurecer|entregar|elevar|baixar|cortar|simplificar|unificar|vamos|faremos|propomos|proposta)(?!\w)/i;
my $NUMT = qr/(R\$\s?[\d.,]+|(?<!\w)\d+(?:[.,]\d+)?\s?%|(?<!\w)\d[\d.,]*\s?(?:mil|milh[õo]es|bilh[õo]es)(?!\w)|(?<!\w)at[ée] 20[23]\d(?!\w)|(?<!\w)metas?(?!\w))/i;

my %files;
for my $f (glob('BR/2026*.pdf'), glob('SP/2026*.pdf')) { my ($sq) = $f =~ /(\d{12})_\d\d\.pdf$/; push @{$files{$sq}}, $f }

sub js {
  my $d = shift;
  if (ref $d eq 'HASH') { return '{' . join(',', map { "\"$_\":" . js($d->{$_}) } sort keys %$d) . '}' }
  if (ref $d eq 'ARRAY') { return '[' . join(',', map { js($_) } @$d) . ']' }
  return 'null' unless defined $d;
  return $d if $d =~ /^-?(0|[1-9]\d*)(\.\d+)?$/;
  my $s = $d; $s =~ s/(["\\])/\\$1/g; $s =~ s/[\x00-\x1f]/ /g; "\"$s\"";
}

my %out; my %full;
for my $sq (sort keys %files) {
  my ($txt, $pages, $bytes) = ('', 0, 0);
  for my $f (@{$files{$sq}}) {
    my $t = `pdftotext -enc UTF-8 "$f" - 2>/dev/null`; utf8::decode($t);
    $pages += () = $t =~ /\f/g; $bytes += -s $f; $txt .= "\n$t";
  }
  $txt =~ s/(\w)-\n(\w)/$1$2/g;
  $txt =~ s/[\f\r]/\n/g;
  my @w = $txt =~ /(?<!\w)[[:alpha:]]{2,}(?!\w)/g; my $W = scalar(@w) || 1;
  my $num = () = $txt =~ /$NUMT/g;
  (my $flat = $txt) =~ s/\n(?=[[:lower:](,])/ /g;
  $flat =~ s/[ \t]+/ /g;
  my @sent = grep { length($_) >= 40 && length($_) <= 700 }
             map { my $s = $_; $s =~ s/^\s*[•●▪■\-–·*\d.)]+\s*//; $s =~ s/\s+/ /g; $s =~ s/^\s+|\s+$//g; $s }
             split /(?<=[.;!?])\s+(?=[[:upper:]"“•●▪■\-–])|\n\s*\n|\n(?=\s*[•●▪■\-–·*])|\n(?=\s*\d+[.)]\s)/, $flat;
  my (%cnt, %quotes, %seen);
  for my $t (@T) { my ($k, undef, $re) = @$t; my $n = () = $txt =~ /$re/g; $cnt{$k} = sprintf('%.1f', $n * 10000 / $W) + 0 }
  for my $t (@T) {
    my ($k, undef, $re) = @$t; my @c;
    for my $s (@sent) {
      next if length($s) < 70 || length($s) > 380;
      next unless $s =~ $VERB;
      my $n = () = $s =~ /$re/g; next unless $n;
      next if $s =~ /(\.{4,}|\s{3,}|http|www\.|©|\|)/;
      my $sc = $n * 2 + ($s =~ $NUMT ? 3 : 0) + ($s =~ /^\s*(Vamos|Criar|Ampliar|Implantar|Garantir|Reduzir|Investir|Propomos|Criaremos|Ampliaremos)/i ? 2 : 0);
      push @c, [$sc, $s];
    }
    my @pick;
    for my $c (sort { $b->[0] <=> $a->[0] || length($a->[1]) <=> length($b->[1]) } @c) {
      my $key = lc substr($c->[1], 0, 60); next if $seen{$key}++;
      push @pick, $c->[1]; last if @pick >= 4;
    }
    $quotes{$k} = \@pick;
  }
  $full{$sq} = [ grep { !/(\.{4,}|http|www\.)/ } @sent ];
  $out{$sq} = { pg => $pages, w => $W, mb => sprintf('%.1f', $bytes / 1048576) + 0, conc => sprintf('%.1f', $num * 1000 / $W) + 0,
                t => \%cnt, q => \%quotes, f => [ map { my $x = $_; $x =~ s{^.*/}{}; $x } @{$files{$sq}} ] };
}
print 'window.PLANOS=' . js(\%out) . ";\n";
print 'window.PTXT=' . js(\%full) . ";\n";
print 'window.TEMAS=' . js([ map { [$_->[0], $_->[1]] } @T ]) . ";\n";
