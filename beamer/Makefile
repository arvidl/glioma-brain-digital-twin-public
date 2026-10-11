TEX     = main
LATEXMK = latexmk

.PHONY: pdf clean watch

pdf:
	$(LATEXMK) -pdf -pdflatex="pdflatex -interaction=nonstopmode -shell-escape" $(TEX).tex

clean:
	$(LATEXMK) -C
	rm -f $(TEX).nav $(TEX).snm $(TEX).vrb $(TEX).run.xml $(TEX).bbl $(TEX).bcf

watch:
	$(LATEXMK) -pdf -pvc -pdflatex="pdflatex -interaction=nonstopmode -shell-escape" $(TEX).tex
