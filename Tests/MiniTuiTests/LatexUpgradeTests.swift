import Testing
import MiniTui

@Test("renders legacy font switches and consumes their following spaces")
func rendersLegacyFontSwitches() {
    let source = #"\textnormal{hello}+\mbox{world}+\boldsymbol{x}+{\rm roman}+{\bf bold}+{\it italic}+{\sf sans}+{\tt mono}+{\cal calligraphic}+{\sl slanted}"#
    #expect(renderLatex(source) == "hello+world+x+roman+bold+italic+sans+mono+calligraphic+slanted")
    #expect(renderLatex(#"F_{\rm intrinsic}(\lambda)"#) == "F_intrinsic(λ)")
}

@Test("centers odd case rows on the surrounding equation")
func centersOddCaseRows() {
    let source = #"f(x)=\begin{cases}a & x<0 \\ b & \text{if }x=0 \\ c & \text{otherwise}\end{cases}"#
    #expect(renderLatex(source) == "       ⎧ a if x < 0\nf(x) = ⎨ b if x = 0\n       ⎩ c otherwise")
}

@Test("centers even case rows around a middle brace")
func centersEvenCaseRows() {
    let source = #"f(x) = \begin{cases} x^{2} & x \geq 0 \\ -x & x < 0 \end{cases}"#
    #expect(renderLatex(source) == "       ⎧ x² if x ≥ 0\nf(x) = ⎨\n       ⎩ -x if x < 0")
}

@Test("aligns long case values and keeps the equation on the center row")
func centersLongCaseEquation() {
    let source = #"""
    \Psi(x,t)=
    \sum_{n=1}^{\infty}
    \underbrace{
    c_n
    \sqrt{\frac{2}{L}}
    \sin\!\left(\frac{n\pi x}{L}\right)
    }_{\text{spatial eigenmode}}
    \exp\!\left(-\frac{i\hbar n^2\pi^2}{2mL^2}t\right),
    \qquad
    |\Psi(x,t)|^2
    =
    \begin{cases}
    \Psi^\ast\Psi, & 0<x<L,\\
    0, & \text{otherwise}.
    \end{cases}
    """#
    let expected = String(repeating: " ", count: 97) + "⎧ Ψ^∗Ψ if 0 < x < L,\n"
        + "Ψ(x,t) = ∑ₙ₌₁^∞ cₙ √(2/L) sin((nπ x)/L)_(spatial eigenmode) exp(-(iℏ n²π²)/(2mL²)t), |Ψ(x,t)|² = ⎨\n"
        + String(repeating: " ", count: 97) + "⎩ 0    otherwise."
    #expect(renderLatex(source) == expected)
}

@Test("lays out unsupported and nested display scripts while keeping fractions linear")
func laysOutDisplayScripts() {
    let source = #"\partial_tU_2(t,0)=Aj_*(1-t)^{-A-1}.\qquad x^{n^2}+x_{i_j}"#
    #expect(
        renderLatex(source, options: RenderLatexOptions(display: true))
            == "                            2\n                    -A-1   n\n∂ₜU₂(t,0) = Aj (1-t)    . x  +x\n              *                i\n                                j"
    )
    #expect(renderLatex(#"e^{\frac{1}{2}}+\tfrac{1}{2}"#, options: RenderLatexOptions(display: true)) == "e^(1/2)+1/2")
}
