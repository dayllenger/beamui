module beamui.dml.annotations;

/// Annotate widget with @dmlwidget UDA to allow using it in DML
struct dmlwidget
{
    bool dummy;
}

/// Annotate widget property with @dmlproperty UDA to allow using it in DML
struct dmlproperty
{
    bool dummy;
}

/// Annotate signal with @dmlsignal UDA
struct dmlsignal
{
    bool dummy;
}
