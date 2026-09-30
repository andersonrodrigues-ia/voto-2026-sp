# Voto 2026 · São Paulo

Painel interativo para comparar os candidatos das eleições gerais de 2026 (1º turno em 4 de outubro): Presidente e, em São Paulo, Governador, Senado, Deputado federal e Deputado estadual.

**Acesse:** https://andersonrodrigues-ia.github.io/voto-2026-sp/

## O que tem

- **Todos os candidatos**, com número de urna, vice ou suplentes, situação do registro, perfil, patrimônio declarado e trajetória eleitoral desde 1982.
- **Atuação no poder público**: proposições apresentadas e as que viraram lei na Câmara dos Deputados (desde 2003), no Senado e na Assembleia Legislativa de SP. As leis simbólicas (nomes de vias, utilidade pública, datas comemorativas, títulos) aparecem separadas das leis de conteúdo.
- **Agenda do Executivo**: proposições enviadas ao Legislativo pelo governo federal (2003–2010 e 2023–2026) e pelo governo paulista (2023–2026), e quantas viraram lei.
- **Planos de governo** de Presidente e Governador: busca livre no texto, ênfase por tema, trechos por tema e download do PDF oficial.
- **Comparação** de até 4 candidatos do mesmo cargo, lado a lado.
- **Pesquisas** de intenção de voto mais recentes, com instituto e registro no TSE.
- **Minha cola**: monte os números na ordem das telas da urna e baixe em texto.

## Fontes

Todos os dados são públicos e oficiais:

- [Portal de Dados Abertos do TSE](https://dadosabertos.tse.jus.br/): candidaturas, bens declarados (2014–2026), histórico de candidaturas, candidatos de 1994 a 2002, votação de 1982 a 1990 e de 2004 a 2016, fotos e planos de governo.
- [Dados Abertos da Câmara dos Deputados](https://dadosabertos.camara.leg.br/): proposições e autores, 2003–2026.
- [Dados Abertos do Senado Federal](https://legis.senado.leg.br/dadosabertos/): matérias e autorias.
- [Dados Abertos da Alesp](https://www.al.sp.gov.br/dados-abertos/): proposituras, autores e tramitação.
- Pesquisas: Datafolha (registro BR-00304/2026) e Real Time Big Data (registro SP-06293/2026).

Dados extraídos em 30/09/2026. A situação dos registros pode mudar até a eleição.

## Como ler

- Contagens por tema nos planos medem ênfase no texto, não qualidade da proposta.
- Trechos dos planos são frases literais selecionadas automaticamente; confira o contexto no PDF.
- Patrimônio é o declarado pelo candidato, em valores nominais.
- Quantidade de proposições não mede relevância; leia as ementas na ficha de cada candidato.
- O balanço de gestão citado nos planos é afirmação do próprio candidato, sem verificação independente.

Este painel não faz recomendação de voto.

## Estrutura

- `index.html`: o painel, com os dados embutidos.
- `planos/`: PDFs oficiais dos planos de governo (TSE).
- `fotos/`: fotos dos candidatos a deputado (TSE), carregadas sob demanda.
- `scripts/`: scripts em Perl que baixam e consolidam as bases e geram o painel.
