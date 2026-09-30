#!/usr/bin/perl
# Monta: out/artifact/ (index.html + planos/*.pdf + fotos/dep-N.json) e out/local/Voto 2026 SP.html (arquivo único blindado)
use strict; use warnings; use MIME::Base64 qw(encode_base64); use File::Path qw(make_path); use File::Copy qw(copy);

sub slurp { my $f = shift; open my $h, '<:raw', $f or die "$f: $!"; local $/; <$h> }
sub b64 { encode_base64(slurp(shift), '') }
sub mime { my $d = substr(slurp(shift), 0, 4); return 'image/jpeg' if $d =~ /^\xFF\xD8\xFF/; return 'image/png' if $d =~ /^\x89PNG/; return 'font/woff2' if $d eq 'wOF2'; return 'application/pdf' if $d eq '%PDF'; die "tipo desconhecido" }
sub jstr { my $s = shift; $s =~ s/(["\\])/\\$1/g; "\"$s\"" }

my $src   = slurp('painel.src.html');
my $data  = slurp('data.js');
my $plans = slurp('planos.js');
my $legis = slurp('legis.js');
$_ =~ s{</script}{<\\/script}gi for ($data, $plans, $legis);
$plans .= "</script>\n<script>$legis";   # atuação no poder público entra logo após os planos

# quais candidatos são majoritários (foto inline no artifact)
my %maj;
{ use JSON::PP; (my $j = $data) =~ s/^window\.TSE=//; $j =~ s/;\s*$//; $j =~ s{<\\/script}{</script}gi;
  for my $c (@{ JSON::PP->new->decode($j) }) { $maj{"$c->{uf}$c->{sq}"} = 1 unless $c->{cargo} =~ /^DEPUTADO/ } }
print STDERR "majoritarios: ", scalar(keys %maj), "\n";

my @fotos = glob('fotos/F*_div.jpg');
my (%fmaj, %fdep);
for my $f (@fotos) { my ($k) = $f =~ m{F(\w\w\d+)_div\.jpg$}; my $e = [mime($f), b64($f)]; if ($maj{$k}) { $fmaj{"f:$k"} = $e } else { $fdep{"f:$k"} = $e } }
print STDERR "fotos maj=", scalar(keys %fmaj), " dep=", scalar(keys %fdep), "\n";
sub mapjs { my $m = shift; '{' . join(',', map { jstr($_) . ':[' . jstr($m->{$_}[0]) . ',' . jstr($m->{$_}[1]) . ']' } sort keys %$m) . '}' }

my %font = ('font-archivo' => 'fonts/archivo.woff2', 'font-mono' => 'fonts/jbmono.woff2');
my $facecss = '@font-face{font-family:"Archivo";src:url("asset:font-archivo") format("woff2");font-weight:100 900;font-stretch:62% 125%;font-style:normal;font-display:swap}'
            . '@font-face{font-family:"JetBrains Mono";src:url("asset:font-mono") format("woff2");font-weight:700;font-style:normal;font-display:swap}';
my @pdfs = (glob('BR/2026*.pdf'), glob('SP/2026*.pdf'));
my $gen = 'window.__GEN={tse:"30/09/2026, 08h31"};';

# ---------- ARTIFACT ----------
make_path('out/artifact/planos', 'out/artifact/fotos');
copy($_, 'out/artifact/planos/' . (m{([^/]+)$})[0]) or die for @pdfs;
my @keys = sort keys %fdep; my @parts; my ($i, $n, $cur, $sz) = (0, 0, {}, 0);
for my $k (@keys) { $cur->{$k} = $fdep{$k}; $sz += length $fdep{$k}[1];
  if ($sz > 7_500_000) { $n++; push @parts, "fotos/dep-$n.txt"; open my $o, '>:raw', "out/artifact/fotos/dep-$n.txt"; print $o mapjs($cur); close $o; $cur = {}; $sz = 0 } }
if (%$cur) { $n++; push @parts, "fotos/dep-$n.txt"; open my $o, '>:raw', "out/artifact/fotos/dep-$n.txt"; print $o mapjs($cur); close $o }
(my $fc_art = $facecss) =~ s{asset:(font-\w+)}{"data:font/woff2;base64," . b64($font{$1})}ge;
my $art = $src;
$art =~ s{<!--B-FONTS-->}{<style>$fc_art</style>};
$art =~ s{<!--B-DATA-->}{'<script>window.__MODE="artifact";window.__FOTO_PARTS=[' . join(',', map { jstr($_) } @parts) . "];$gen</script>\n<script type=\"application/json\" id=\"b-loader\">" . mapjs(\%fmaj) . "</script>\n<script>$data</script>\n<script>$plans</script>"}e;
open my $o, '>:raw', 'out/artifact/index.html' or die; print $o $art; close $o;

# ---------- LOCAL (arquivo único, resiste ao Ctrl+S) ----------
make_path('out/local');
my %all = (%fmaj, %fdep); $all{$_} = [mime($font{$_}), b64($font{$_})] for keys %font;
my $fontloader = <<'JS';
<script>
/* b-loader: gera as @font-face a partir do bloco inerte b-fontcss. Roda no head e de novo no DOMContentLoaded,
   removendo blocos herdados de um "Salvar como" e deixando o nosso por último na cascata. */
(function(){
  var MAP=null, URLS={};
  function map(){ if(MAP) return MAP; try{ MAP=JSON.parse(document.getElementById("b-loader").textContent); }catch(e){ MAP={}; } return MAP; }
  function url(id){ if(URLS[id]) return URLS[id]; var e=map()[id]; if(!e) return ""; var bin=atob(e[1]), u=new Uint8Array(bin.length); for(var i=0;i<bin.length;i++) u[i]=bin.charCodeAt(i); return URLS[id]=URL.createObjectURL(new Blob([u],{type:e[0]})); }
  function gen(){
    var src=document.getElementById("b-fontcss"); if(!src) return;
    document.querySelectorAll("style[data-bgen]").forEach(function(s){ s.remove(); });
    var st=document.createElement("style"); st.setAttribute("data-bgen","1");
    st.textContent=src.textContent.replace(/asset:([\w-]+)/g,function(m,id){ return url(id); });
    document.head.appendChild(st);
  }
  gen(); document.addEventListener("DOMContentLoaded",gen);
})();
</script>
JS
my $pdfblocks = join("\n", map { my ($f) = m{([^/]+)$}; (my $id = $f) =~ s/\W/_/g; "<script type=\"application/octet-stream\" id=\"pdf-$id\">" . b64($_) . "</script>" } @pdfs);
my $loc = $src;
$loc =~ s{<!--B-FONTS-->}{"<script type=\"application/json\" id=\"b-loader\">" . mapjs(\%all) . "</script>\n<script type=\"text/x-bundled-css\" id=\"b-fontcss\">$facecss</script>\n$fontloader"}e;
$loc =~ s{<!--B-DATA-->}{"<script>window.__MODE=\"local\";$gen</script>\n$pdfblocks\n<script>$data</script>\n<script>$plans</script>"}e;
# documento completo para abrir direto no navegador
my ($title) = $loc =~ m{(<title>.*?</title>)}s; $loc =~ s{<title>.*?</title>\n?}{}s;
my ($head, $body) = $loc =~ m{^(.*?</style>)(.*)$}s;
$loc = "<!doctype html>\n<html lang=\"pt-BR\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1,viewport-fit=cover\">$title\n$head\n</head><body>$body\n</body></html>\n";
open $o, '>:raw', 'out/local/Voto 2026 SP.html' or die; print $o $loc; close $o;
printf STDERR "artifact index=%.1f MB, partes=%d; local=%.1f MB\n", (-s 'out/artifact/index.html') / 1048576, scalar(@parts), (-s 'out/local/Voto 2026 SP.html') / 1048576;
