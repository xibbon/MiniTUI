import Testing
import MiniTui

@Test("renders inline fractions, scripts, symbols, and roots")
func rendersBasicLatex() {
    #expect(renderLatex(#"\frac{x^2+1}{x-1}"#) == "(x²+1)/(x-1)")
    #expect(renderLatex(#"x_1^2 + y_{i=0}"#) == "x₁² + yᵢ₌₀")
    #expect(renderLatex(#"\alpha+\Gamma+\infty+\partial"#) == "α+Γ+∞+∂")
    #expect(renderLatex(#"\sqrt{x}+\sqrt[3]{y}+\sqrt{k+1}"#) == "√x+∛y+√(k+1)")
}

@Test("renders operators and relations with v0.84.1 spacing")
func rendersLatexSpacing() {
    #expect(renderLatex(#"x\neq0"#) == "x ≠ 0")
    #expect(renderLatex(#"\pi\cdot\frac{1}{\pi}"#) == "π · 1/π")
    #expect(renderLatex(#"i\sin\theta"#) == "i sin θ")
    #expect(renderLatex(#"\det(A)"#) == "det(A)")
    #expect(renderLatex("x\n=\ny") == "x = y")
}

@Test("renders aligned equations")
func rendersAlignedLatex() {
    let source = #"\begin{aligned}a&=b\\c&=d\end{aligned}"#
    #expect(renderLatex(source) == "a = b\nc = d")
}

@Test("renders case conditions with three brace forms")
func rendersLatexCases() {
    let source = #"\begin{cases}a & x<0 \\ b & x=0 \\ c & \text{otherwise}\end{cases}"#
    #expect(renderLatex(source) == "⎧ a if x < 0\n⎨ b if x = 0\n⎩ c otherwise")
}

@Test("renders matrices with aligned columns")
func rendersLatexMatrix() {
    let source = #"\begin{pmatrix}1&200\\3000&4\end{pmatrix}"#
    #expect(renderLatex(source) == "⎛ 1    │ 200 ⎞\n⎝ 3000 │ 4   ⎠")
}

@Test("stacks display fractions and operator limits")
func rendersDisplayLatexLayouts() {
    #expect(
        renderLatex(
            #"\frac{x^2+1}{x-1}"#,
            options: RenderLatexOptions(display: true)
        ) == "x²+1\n────\nx-1"
    )
    #expect(
        renderLatex(
            #"\sum_{i=0}^n x_i"#,
            options: RenderLatexOptions(display: true)
        ) == " n\n ∑  xᵢ\ni=0"
    )
}

@Test("composes a matrix that contains fractions")
func composesMatrixFractions() {
    let source = #"R\left(\frac{\pi}{4}\right)=\begin{pmatrix}\frac{\sqrt{2}}{2}&-\frac{\sqrt{2}}{2}\\\frac{\sqrt{2}}{2}&\frac{\sqrt{2}}{2}\end{pmatrix}."#
    #expect(
        renderLatex(source, options: RenderLatexOptions(display: true))
            == "   π\nR( ─ ) = ⎛ (√2)/2 │ -(√2)/2 ⎞\n   4     ⎝ (√2)/2 │ (√2)/2  ⎠."
    )
}

@Test("keeps adjacent matrices separated")
func composesAdjacentMatrices() {
    let source = #"R\left(\frac{\pi}{4}\right) \begin{pmatrix}1\\0\end{pmatrix}=\begin{pmatrix}\frac{\sqrt{2}}{2}\\\frac{\sqrt{2}}{2}\end{pmatrix}."#
    #expect(
        renderLatex(source, options: RenderLatexOptions(display: true))
            == "   π\nR( ─ ) ⎛ 1 ⎞ = ⎛ (√2)/2 ⎞\n   4   ⎝ 0 ⎠   ⎝ (√2)/2 ⎠."
    )
}

@Test("returns nil for unsupported and malformed LaTeX")
func rejectsUnsupportedLatex() {
    #expect(renderLatex(#"x + \unknown{y}"#) == nil)
    #expect(renderLatex(#"\frac{1}{x"#) == nil)
}
