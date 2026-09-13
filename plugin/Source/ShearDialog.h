// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vixen420
//
// Shear for Illustrator is free software: you may redistribute it and/or
// modify it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or (at your
// option) any later version. It comes with ABSOLUTELY NO WARRANTY. See the
// file LICENSE, or <https://www.gnu.org/licenses/>, for the full text.
//
// Additional permission under GPL-3.0 section 7: this file may be combined with
// the Adobe Illustrator SDK, whose sample framework sources are compiled into
// every plugin built from it. See LICENSE-EXCEPTION.

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
    values it held on entry, so a canceled preview leaves no trace. */
bool RunShearDialog(ShearDialogState& state);

/** Releases what the dialog registered with the window manager. Called when the
    plugin shuts down; safe to call when the dialog has never been opened. */
void ShutdownShearDialog();

#endif // __SHEARDIALOG_H__
