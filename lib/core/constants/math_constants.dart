/// Threshold for treating a parameter value as "effectively zero / neutral."
///
/// Used in pass-activity checks (sharpen amount, denoise amount, slider isNeutral)
/// and anywhere a floating-point parameter comparison should tolerate tiny rounding
/// errors rather than requiring exact equality.
const double kParamEpsilon = 0.001;
