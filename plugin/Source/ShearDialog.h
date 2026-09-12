//  ShearDialog.h -- the modal parameter dialog for the Shear effect.

#ifndef __SHEARDIALOG_H__
#define __SHEARDIALOG_H__

#include "IllustratorSDK.h"
#include "AILiveEffect.h"

struct ShearDialogState
{
    double shearAngle = 0.0;
    double axisAngle = 0.0;
    /** True when Illustrator will accept live preview updates. */
    bool allowPreview = false;
    /** Set from the dialog's own Preview check box. */
    bool previewEnabled = true;
    AILiveEffectParamContext context = nullptr;
    AILiveEffectParameters parameters = nullptr;
};

/** Runs the dialog modally. Returns true when the user commits, false on
    cancel. On cancel the caller's parameter dictionary is restored to the
    values it held on entry, so a cancelled preview leaves no trace. */
bool RunShearDialog(ShearDialogState& state);

#endif // __SHEARDIALOG_H__
