#!/bin/bash
set -eu
# --------------------------------------------------------------------------------
#  Usage Description Function
# --------------------------------------------------------------------------------

script_name=$(basename "${0}")

show_usage() {
	cat <<EOF

${script_name}: Sub-script of PostFreeSurferPipeline.sh

EOF
}

# Allow script to return a Usage statement, before any other output or checking
if [ "$#" = "0" ]; then
    show_usage
    exit 1
fi

# ------------------------------------------------------------------------------
#  Check that HCPPIPEDIR is defined and Load Function Libraries
# ------------------------------------------------------------------------------

if [ -z "${HCPPIPEDIR}" ]; then
  echo "${script_name}: ABORTING: HCPPIPEDIR environment variable must be set"
  exit 1
fi

source "${HCPPIPEDIR}/global/scripts/debug.shlib" "$@"         # Debugging functions; also sources log.shlib
source ${HCPPIPEDIR}/global/scripts/opts.shlib                 # Command line option functions

opts_ShowVersionIfRequested $@

if opts_CheckForHelpRequest $@; then
	show_usage
	exit 0
fi

# ------------------------------------------------------------------------------
#  Verify required environment variables are set and log value
# ------------------------------------------------------------------------------

log_Check_Env_Var HCPPIPEDIR
log_Check_Env_Var FSLDIR
log_Check_Env_Var CARET7DIR

# ------------------------------------------------------------------------------
#  Start work
# ------------------------------------------------------------------------------

log_Msg "START"

StudyFolder="${1}"
Subject="${2}"
AtlasSpaceFolder="${3}"
NativeFolder="${4}"
T1wFolder="${5}"
HighResMesh="${6}"
LowResMeshes="${7}"
OrginalT1wImage="${8}"
OrginalT2wImage="${9}"
T1wImageBrainMask="${10}"
InitialT1wTransform="${11}"
dcT1wTransform="${12}"
InitialT2wTransform="${13}"
dcT2wTransform="${14}"
FinalT2wTransform="${15}"
AtlasTransform="${16}"
BiasField="${17}"
OutputT1wImage="${18}"
OutputT1wImageRestore="${19}"
OutputT1wImageRestoreBrain="${20}"
OutputMNIT1wImage="${21}"
OutputMNIT1wImageRestore="${22}"
OutputMNIT1wImageRestoreBrain="${23}"
OutputT2wImage="${24}"
OutputT2wImageRestore="${25}"
OutputT2wImageRestoreBrain="${26}"
OutputMNIT2wImage="${27}"
OutputMNIT2wImageRestore="${28}"
OutputMNIT2wImageRestoreBrain="${29}"
OutputOrigT1wToT1w="${30}"
OutputOrigT1wToStandard="${31}"
OutputOrigT2wToT1w="${32}"
OutputOrigT2wToStandard="${33}"
BiasFieldOutput="${34}"
T1wMNIImageBrainMask="${35}"
Jacobian="${36}"
ReferenceMyelinMaps="${37}"
CorrectionSigma="${38}"
RegName="${39}"
UseIndMean="${40}"

log_Msg "RegName: ${RegName}"

verbose_echo " "
verbose_red_echo " ===> Running ${script_name}"
verbose_echo " "

# -- check for presence of T2w image
if [ `${FSLDIR}/bin/imtest ${OrginalT2wImage}` -eq 0 ]; then
  T2wPresent="NO"
else
  T2wPresent="YES"
fi


LeftGreyRibbonValue="3"
RightGreyRibbonValue="42"
MyelinMappingFWHM="5"
SurfaceSmoothingFWHM="4"
MyelinMappingSigma=`echo "$MyelinMappingFWHM / ( 2 * ( sqrt ( 2 * l ( 2 ) ) ) )" | bc -l`
SurfaceSmoothingSigma=`echo "$SurfaceSmoothingFWHM / ( 2 * ( sqrt ( 2 * l ( 2 ) ) ) )" | bc -l`

IFS=' @' read -a LowResMeshesArray <<< "${LowResMeshes}"

${CARET7DIR}/wb_command -volume-palette $Jacobian MODE_AUTO_SCALE -interpolate true -disp-pos true -disp-neg false -disp-zero false -palette-name HSB8_clrmid -thresholding THRESHOLD_TYPE_NORMAL THRESHOLD_TEST_SHOW_OUTSIDE 0.5 2

# Create one-step resampled versions of the {T1w,T2w}_acpc_dc and {T1w,T2w}_acpc_dc_restore volumes (in T1w space)
# Relative to the one-step resampling in PreFreeSurfer, we:
# (1) now have a better estimate of the brain mask available, using FreeSurfer outputs
# (2) refine the T2wToT1w registration by postpending (via --postmat argument) the "T2wtoT1w.mat" registration
#     generated by FreeSurferPipeline.
# [An implication of (2) is that FreeSurferPipeline should NOT be run using the T2w_acpc_dc.nii.gz output
# by this script (CreateMyelinMaps) because then we'd lose this refinement in the T2wToT1w registration.
# To detect this situation, and prevent FreeSurferPipeline from running after PostFreeSurferPipeline,
# FreeSurferPipeline errors out if the one-step warpfield created here ($OutputOrigT1wToT1w) already exists.]

convertwarp --relout --rel --ref="$T1wImageBrainMask" --premat="$InitialT1wTransform" --warp1="$dcT1wTransform" --out="$OutputOrigT1wToT1w"
applywarp --rel --interp=spline -i "$OrginalT1wImage" -r "$T1wImageBrainMask" -w "$OutputOrigT1wToT1w" -o "$OutputT1wImage"
fslmaths "$OutputT1wImage" -abs "$OutputT1wImage" -odt float
fslmaths "$OutputT1wImage" -div "$BiasField" "$OutputT1wImageRestore"
fslmaths "$OutputT1wImageRestore" -mas "$T1wImageBrainMask" "$OutputT1wImageRestoreBrain"

if [ "${T2wPresent}" = "YES" ] ; then
  convertwarp --relout --rel --ref="$T1wImageBrainMask" --premat="$InitialT2wTransform" --warp1="$dcT2wTransform" --postmat="$FinalT2wTransform" --out="$OutputOrigT2wToT1w"
  applywarp --rel --interp=spline -i "$OrginalT2wImage" -r "$T1wImageBrainMask" -w "$OutputOrigT2wToT1w" -o "$OutputT2wImage"
  fslmaths "$OutputT2wImage" -abs "$OutputT2wImage" -odt float
  fslmaths "$OutputT2wImage" -div "$BiasField" "$OutputT2wImageRestore"
  fslmaths "$OutputT2wImageRestore" -mas "$T1wImageBrainMask" "$OutputT2wImageRestoreBrain"
fi

# Do the same for the equivalents in MNINonLinear space
convertwarp --relout --rel --ref="$OutputMNIT1wImage" --warp1="$OutputOrigT1wToT1w" --warp2="$AtlasTransform" --out="$OutputOrigT1wToStandard"
applywarp --rel --interp=spline -i "$BiasField" -r "$OutputMNIT1wImage" -w "$AtlasTransform" -o "$BiasFieldOutput"
fslmaths "$BiasFieldOutput" -thr 0.1 "$BiasFieldOutput"

applywarp --rel --interp=spline -i "$OrginalT1wImage" -r "$OutputMNIT1wImage" -w "$OutputOrigT1wToStandard" -o "$OutputMNIT1wImage"
fslmaths "$OutputMNIT1wImage" -abs "$OutputMNIT1wImage" -odt float
fslmaths "$OutputMNIT1wImage" -div "$BiasFieldOutput" "$OutputMNIT1wImageRestore"
fslmaths "$OutputMNIT1wImageRestore" -mas "$T1wMNIImageBrainMask" "$OutputMNIT1wImageRestoreBrain"

if [ "${T2wPresent}" = "YES" ] ; then
  convertwarp --relout --rel --ref="$OutputMNIT1wImage" --warp1="$OutputOrigT2wToT1w" --warp2="$AtlasTransform" --out="$OutputOrigT2wToStandard"
  applywarp --rel --interp=spline -i "$OrginalT2wImage" -r "$OutputMNIT1wImage" -w "$OutputOrigT2wToStandard" -o "$OutputMNIT2wImage"
  fslmaths "$OutputMNIT2wImage" -abs "$OutputMNIT2wImage" -odt float
  fslmaths "$OutputMNIT2wImage" -div "$BiasFieldOutput" "$OutputMNIT2wImageRestore"
  fslmaths "$OutputMNIT2wImageRestore" -mas "$T1wMNIImageBrainMask" "$OutputMNIT2wImageRestoreBrain"
fi

# Create T1w/T2w maps
if [ "${T2wPresent}" = "YES" ] ; then  
  ${CARET7DIR}/wb_command -volume-math "clamp((T1w / T2w), 0, 100)" "$T1wFolder"/T1wDividedByT2w.nii.gz -var T1w "$OutputT1wImage".nii.gz -var T2w "$OutputT2wImage".nii.gz -fixnan 0
  ${CARET7DIR}/wb_command -volume-palette "$T1wFolder"/T1wDividedByT2w.nii.gz MODE_AUTO_SCALE_PERCENTAGE -pos-percent 4 96 -interpolate true -palette-name videen_style -disp-pos true -disp-neg false -disp-zero false
  ${CARET7DIR}/wb_command -add-to-spec-file "$T1wFolder"/"$NativeFolder"/"$Subject".native.wb.spec INVALID "$T1wFolder"/T1wDividedByT2w.nii.gz
  ${CARET7DIR}/wb_command -volume-math "(T1w / T2w) * (((ribbon > ($LeftGreyRibbonValue - 0.01)) * (ribbon < ($LeftGreyRibbonValue + 0.01))) + ((ribbon > ($RightGreyRibbonValue - 0.01)) * (ribbon < ($RightGreyRibbonValue + 0.01))))" "$T1wFolder"/T1wDividedByT2w_ribbon.nii.gz -var T1w "$OutputT1wImage".nii.gz -var T2w "$OutputT2wImage".nii.gz -var ribbon "$T1wFolder"/ribbon.nii.gz
  ${CARET7DIR}/wb_command -volume-palette "$T1wFolder"/T1wDividedByT2w_ribbon.nii.gz MODE_AUTO_SCALE_PERCENTAGE -pos-percent 4 96 -interpolate true -palette-name videen_style -disp-pos true -disp-neg false -disp-zero false
  ${CARET7DIR}/wb_command -add-to-spec-file "$T1wFolder"/"$NativeFolder"/"$Subject".native.wb.spec INVALID "$T1wFolder"/T1wDividedByT2w_ribbon.nii.gz
fi


MapListFunc="corrThickness@shape"
if [ "${T2wPresent}" = "YES" ] ; then
  MapListFunc+=" MyelinMap@func SmoothedMyelinMap@func"
fi

for Hemisphere in L R ; do
  if [ $Hemisphere = "L" ] ; then
    Structure="CORTEX_LEFT"
    ribbon="$LeftGreyRibbonValue"
  elif [ $Hemisphere = "R" ] ; then
    Structure="CORTEX_RIGHT"
    ribbon="$RightGreyRibbonValue"
  fi
  if [ ${RegName} = "MSMSulc" ] ; then
    RegSphere="${AtlasSpaceFolder}/${NativeFolder}/${Subject}.${Hemisphere}.sphere.MSMSulc.native.surf.gii"
  else
    RegSphere="${AtlasSpaceFolder}/${NativeFolder}/${Subject}.${Hemisphere}.sphere.reg.reg_LR.native.surf.gii"
  fi

  ${CARET7DIR}/wb_command -metric-regression "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".thickness.native.shape.gii "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".corrThickness.native.shape.gii -roi "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii -remove "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".curvature.native.shape.gii

  #Reduce memory usage by smoothing on downsampled mesh
  LowResMesh="${LowResMeshesArray[0]}"
  
  if [ "${T2wPresent}" = "YES" ] ; then
    ${CARET7DIR}/wb_command -volume-math "(ribbon > ($ribbon - 0.01)) * (ribbon < ($ribbon + 0.01))" "$T1wFolder"/temp_ribbon.nii.gz -var ribbon "$T1wFolder"/ribbon.nii.gz
    ${CARET7DIR}/wb_command -volume-to-surface-mapping "$T1wFolder"/T1wDividedByT2w.nii.gz "$T1wFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".MyelinMap.native.func.gii -myelin-style "$T1wFolder"/temp_ribbon.nii.gz "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".thickness.native.shape.gii "$MyelinMappingSigma"
    rm "$T1wFolder"/temp_ribbon.nii.gz
    ${CARET7DIR}/wb_command -metric-smoothing "$T1wFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".MyelinMap.native.func.gii "$SurfaceSmoothingSigma" "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".SmoothedMyelinMap.native.func.gii -roi "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii  
  fi

  for STRING in $MapListFunc ; do
    Map=`echo $STRING | cut -d "@" -f 1`
    Ext=`echo $STRING | cut -d "@" -f 2`
    ${CARET7DIR}/wb_command -set-map-name "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Map".native."$Ext".gii 1 "$Subject"_"$Hemisphere"_"$Map"
    ${CARET7DIR}/wb_command -metric-palette "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Map".native."$Ext".gii MODE_AUTO_SCALE_PERCENTAGE -pos-percent 4 96 -interpolate true -palette-name videen_style -disp-pos true -disp-neg false -disp-zero false
    ${CARET7DIR}/wb_command -metric-resample "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Map".native."$Ext".gii ${RegSphere} "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".sphere."$HighResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$AtlasSpaceFolder"/"$Subject"."$Hemisphere"."$Map"."$HighResMesh"k_fs_LR."$Ext".gii -area-surfs "$T1wFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".midthickness."$HighResMesh"k_fs_LR.surf.gii -current-roi "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii
    ${CARET7DIR}/wb_command -metric-mask "$AtlasSpaceFolder"/"$Subject"."$Hemisphere"."$Map"."$HighResMesh"k_fs_LR."$Ext".gii "$AtlasSpaceFolder"/"$Subject"."$Hemisphere".atlasroi."$HighResMesh"k_fs_LR.shape.gii "$AtlasSpaceFolder"/"$Subject"."$Hemisphere"."$Map"."$HighResMesh"k_fs_LR."$Ext".gii
    for LowResMesh in "${LowResMeshesArray[@]}" ; do
      ${CARET7DIR}/wb_command -metric-resample "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere"."$Map".native."$Ext".gii ${RegSphere} "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Map"."$LowResMesh"k_fs_LR."$Ext".gii -area-surfs "$T1wFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".midthickness.native.surf.gii "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".midthickness."$LowResMesh"k_fs_LR.surf.gii -current-roi "$AtlasSpaceFolder"/"$NativeFolder"/"$Subject"."$Hemisphere".roi.native.shape.gii
      ${CARET7DIR}/wb_command -metric-mask "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Map"."$LowResMesh"k_fs_LR."$Ext".gii "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere".atlasroi."$LowResMesh"k_fs_LR.shape.gii "$AtlasSpaceFolder"/fsaverage_LR"$LowResMesh"k/"$Subject"."$Hemisphere"."$Map"."$LowResMesh"k_fs_LR."$Ext".gii
    done
  done
done

LowResMeshList=""
for LowResMesh in "${LowResMeshesArray[@]}" ; do
  LowResMeshList+="${AtlasSpaceFolder}/fsaverage_LR${LowResMesh}k@${LowResMesh}k_fs_LR@atlasroi "
done

#Create CIFTI Files
for STRING in "$AtlasSpaceFolder"/"$NativeFolder"@native@roi "$AtlasSpaceFolder"@"$HighResMesh"k_fs_LR@atlasroi ${LowResMeshList} ; do
  Folder=`echo $STRING | cut -d "@" -f 1`
  Mesh=`echo $STRING | cut -d "@" -f 2`
  ROI=`echo $STRING | cut -d "@" -f 3`

  for STRINGII in $MapListFunc ; do
    Map=`echo $STRINGII | cut -d "@" -f 1`
    Ext=`echo $STRINGII | cut -d "@" -f 2`
    ${CARET7DIR}/wb_command -cifti-create-dense-scalar "$Folder"/"$Subject".${Map}."$Mesh".dscalar.nii -left-metric "$Folder"/"$Subject".L.${Map}."$Mesh"."$Ext".gii -roi-left "$Folder"/"$Subject".L."$ROI"."$Mesh".shape.gii -right-metric "$Folder"/"$Subject".R.${Map}."$Mesh"."$Ext".gii -roi-right "$Folder"/"$Subject".R."$ROI"."$Mesh".shape.gii
    ${CARET7DIR}/wb_command -set-map-names "$Folder"/"$Subject".${Map}."$Mesh".dscalar.nii -map 1 "${Subject}_${Map}"
    ${CARET7DIR}/wb_command -cifti-palette "$Folder"/"$Subject".${Map}."$Mesh".dscalar.nii MODE_AUTO_SCALE_PERCENTAGE "$Folder"/"$Subject".${Map}."$Mesh".dscalar.nii -pos-percent 4 96 -interpolate true -palette-name videen_style -disp-pos true -disp-neg false -disp-zero false
  done
done

# Create surface on HighResMesh in subject's T1w space
${CARET7DIR}/wb_command -surface-resample ${StudyFolder}/${Subject}/T1w/${NativeFolder}/${Subject}.L.midthickness.native.surf.gii \
	${AtlasSpaceFolder}/${NativeFolder}/${Subject}.L.sphere.MSMSulc.native.surf.gii \
	${AtlasSpaceFolder}/${Subject}.L.sphere.${HighResMesh}k_fs_LR.surf.gii \
	BARYCENTRIC ${StudyFolder}/${Subject}/T1w/${Subject}.L.midthickness.${HighResMesh}k_fs_LR.surf.gii
${CARET7DIR}/wb_command -surface-resample ${StudyFolder}/${Subject}/T1w/${NativeFolder}/${Subject}.R.midthickness.native.surf.gii \
	${AtlasSpaceFolder}/${NativeFolder}/${Subject}.R.sphere.MSMSulc.native.surf.gii \
	${AtlasSpaceFolder}/${Subject}.R.sphere.${HighResMesh}k_fs_LR.surf.gii \
	BARYCENTRIC ${StudyFolder}/${Subject}/T1w/${Subject}.R.midthickness.${HighResMesh}k_fs_LR.surf.gii
		
# BC processing
if [ "${T2wPresent}" = "YES" ] ; then	
	# determine the resolution of the reference myelin map
	IsRefValid=false
	# append the HighResMesh into the full ResMesh array
	AllAvailableMeshesArray="${LowResMeshesArray[@]}"
	AllAvailableMeshesArray+=(${HighResMesh})
	NumRefSurfVertices=$(${CARET7DIR}/wb_command -file-information "$ReferenceMyelinMaps" -only-cifti-xml | grep -m 1 -oP 'SurfaceNumberOf(Vertices|Nodes)="\K\d+')
	# compare vertex numbers between mesh files in the template directory and the input reference myelin map
	for ResMesh in "${AllAvailableMeshesArray[@]}" ; do
		NumSurfVertices=$(grep -m 1 -oP 'Dim0="\K\d+' ${HCPPIPEDIR}/global/templates/standard_mesh_atlases/L.atlasroi.${ResMesh}k_fs_LR.shape.gii)
		if [ "$NumRefSurfVertices" = "$NumSurfVertices" ]; then
			RefResMesh=${ResMesh}
			IsRefValid=true
			log_Msg "Find the template file with the same resolution mesh as the reference myelin map! The ResMesh is ${RefResMesh}"
			break
		fi
	done
	
	# error when the number of vertex doesn't have a match
	if [ "$IsRefValid" = false ]; then
		log_Err_Abort "The mesh resolution of the input reference map ${ReferenceMyelinMaps} doesn't match with any template files in ${HCPPIPEDIR}/global/templates/standard_mesh_atlases!"
	fi
	
	case "$RefResMesh" in
		(${HighResMesh})
			SphereFolder=${AtlasSpaceFolder}
			T1wSurfFolder=${StudyFolder}/${Subject}/T1w
			;;
		(*)
			SphereFolder=${AtlasSpaceFolder}/fsaverage_LR${RefResMesh}k
			T1wSurfFolder=${StudyFolder}/${Subject}/T1w/fsaverage_LR${RefResMesh}k
			;;
	esac

	#Reduce memory usage by smoothing on downsampled mesh (match the gifti version by using the first lowresmesh)
	LowResMesh="${LowResMeshesArray[0]}"
	MyelinTargetFile=${ReferenceMyelinMaps}
	# only resample the reference map into low res mesh if it isn't the first LowResMesh
	if [ "$RefResMesh" != "${LowResMesh}" ]; then
		log_Msg "resample the reference map with ${NumRefSurfVertices} ~ ${RefResMesh}k vertices into low res mesh"
		MyelinTargetFile=${AtlasSpaceFolder}/fsaverage_LR${LowResMesh}k/${Subject}.RefMyelinMap.${LowResMesh}k_fs_LR.dscalar.nii
		${CARET7DIR}/wb_command -cifti-resample ${ReferenceMyelinMaps} \
				COLUMN ${AtlasSpaceFolder}/fsaverage_LR${LowResMesh}k/${Subject}.MyelinMap.${LowResMesh}k_fs_LR.dscalar.nii \
				COLUMN ADAP_BARY_AREA ENCLOSING_VOXEL \
				${MyelinTargetFile} \
				-surface-postdilate 40 \
				-left-spheres ${SphereFolder}/${Subject}.L.sphere.${RefResMesh}k_fs_LR.surf.gii ${AtlasSpaceFolder}/fsaverage_LR${LowResMesh}k/${Subject}.L.sphere.${LowResMesh}k_fs_LR.surf.gii \
				-left-area-surfs ${T1wSurfFolder}/${Subject}.L.midthickness.${RefResMesh}k_fs_LR.surf.gii ${StudyFolder}/${Subject}/T1w/fsaverage_LR${LowResMesh}k/${Subject}.L.midthickness.${LowResMesh}k_fs_LR.surf.gii \
				-right-spheres ${SphereFolder}/${Subject}.R.sphere.${RefResMesh}k_fs_LR.surf.gii ${AtlasSpaceFolder}/fsaverage_LR${LowResMesh}k/${Subject}.R.sphere.${LowResMesh}k_fs_LR.surf.gii \
				-right-area-surfs ${T1wSurfFolder}/${Subject}.R.midthickness.${RefResMesh}k_fs_LR.surf.gii ${StudyFolder}/${Subject}/T1w/fsaverage_LR${LowResMesh}k/${Subject}.R.midthickness.${LowResMesh}k_fs_LR.surf.gii
	fi
	# the gifti files from reference maps are generated in previous versions
	${CARET7DIR}/wb_command -cifti-separate "$ReferenceMyelinMaps" COLUMN \
		-metric CORTEX_LEFT "$SphereFolder"/"$Subject".L.RefMyelinMap."$RefResMesh"k_fs_LR.func.gii \
		-metric CORTEX_RIGHT "$SphereFolder"/"$Subject".R.RefMyelinMap."$RefResMesh"k_fs_LR.func.gii
	
	# ----- Begin moved statements -----
	# Recompute Myelin Map Bias Field Based on Better Registration
	log_Msg "Recompute Myelin Map Bias Field Based on Better Registration"
	# Myelin Map BC using low res
	"$HCPPIPEDIR"/global/scripts/MyelinMap_BC.sh \
		--study-folder="$StudyFolder" \
		--subject="$Subject" \
		--registration-name="MSMSulc" \
		--use-ind-mean="$UseIndMean" \
		--low-res-mesh="$LowResMesh" \
		--myelin-target-file="$MyelinTargetFile" \
		--map="MyelinMap"
	# ----- End moved statements -----
	# bias field is computed in the module MyelinMap_BC.sh
	${CARET7DIR}/wb_command -cifti-separate ${AtlasSpaceFolder}/${NativeFolder}/${Subject}.BiasField.native.dscalar.nii COLUMN \
		-metric CORTEX_LEFT ${AtlasSpaceFolder}/${NativeFolder}/${Subject}.L.BiasField.native.func.gii \
		-metric CORTEX_RIGHT ${AtlasSpaceFolder}/${NativeFolder}/${Subject}.R.BiasField.native.func.gii	
	
	# bias field in native space is already generated
	# BC is already applied in module MyelinMap_BC on MyelinMap
	# BC the other types of given myelin maps
	${CARET7DIR}/wb_command -cifti-math "Var - Bias" ${AtlasSpaceFolder}/${NativeFolder}/${Subject}.SmoothedMyelinMap_BC.native.dscalar.nii \
		-var Var ${AtlasSpaceFolder}/${NativeFolder}/${Subject}.SmoothedMyelinMap.native.dscalar.nii \
		-var Bias ${AtlasSpaceFolder}/${NativeFolder}/${Subject}.BiasField.native.dscalar.nii

	# myelin map only loop
	for MyelinMap in MyelinMap SmoothedMyelinMap ; do
		${CARET7DIR}/wb_command -cifti-separate ${AtlasSpaceFolder}/${NativeFolder}/${Subject}.${MyelinMap}_BC.native.dscalar.nii COLUMN \
			-metric CORTEX_LEFT ${AtlasSpaceFolder}/${NativeFolder}/${Subject}.L.${MyelinMap}_BC.native.func.gii \
			-metric CORTEX_RIGHT ${AtlasSpaceFolder}/${NativeFolder}/${Subject}.R.${MyelinMap}_BC.native.func.gii
			
		# create cifti and gifti MyelinMap in the high res mesh space
		${CARET7DIR}/wb_command -cifti-resample ${AtlasSpaceFolder}/${NativeFolder}/${Subject}.${MyelinMap}_BC.native.dscalar.nii \
			COLUMN ${AtlasSpaceFolder}/${Subject}.${MyelinMap}.${HighResMesh}k_fs_LR.dscalar.nii \
			COLUMN ADAP_BARY_AREA ENCLOSING_VOXEL \
			${AtlasSpaceFolder}/${Subject}.${MyelinMap}_BC.${HighResMesh}k_fs_LR.dscalar.nii \
			-surface-postdilate 40 \
			-left-spheres ${AtlasSpaceFolder}/${NativeFolder}/${Subject}.L.sphere.MSMSulc.native.surf.gii ${AtlasSpaceFolder}/${Subject}.L.sphere.${HighResMesh}k_fs_LR.surf.gii \
			-left-area-surfs ${StudyFolder}/${Subject}/T1w/${NativeFolder}/${Subject}.L.midthickness.native.surf.gii ${StudyFolder}/${Subject}/T1w/${Subject}.L.midthickness.${HighResMesh}k_fs_LR.surf.gii \
			-right-spheres ${AtlasSpaceFolder}/${NativeFolder}/${Subject}.R.sphere.MSMSulc.native.surf.gii ${AtlasSpaceFolder}/${Subject}.R.sphere.${HighResMesh}k_fs_LR.surf.gii \
			-right-area-surfs ${StudyFolder}/${Subject}/T1w/${NativeFolder}/${Subject}.R.midthickness.native.surf.gii ${StudyFolder}/${Subject}/T1w/${Subject}.R.midthickness.${HighResMesh}k_fs_LR.surf.gii
		# gifti files
		${CARET7DIR}/wb_command -cifti-separate ${AtlasSpaceFolder}/${Subject}.${MyelinMap}_BC.${HighResMesh}k_fs_LR.dscalar.nii COLUMN \
			-metric CORTEX_LEFT ${AtlasSpaceFolder}/${Subject}.L.${MyelinMap}_BC.${HighResMesh}k_fs_LR.func.gii \
			-metric CORTEX_RIGHT ${AtlasSpaceFolder}/${Subject}.R.${MyelinMap}_BC.${HighResMesh}k_fs_LR.func.gii
	done
	# remove intermediate files
	# rm ${StudyFolder}/${Subject}/T1w/${Subject}.L.midthickness.${HighResMesh}k_fs_LR.surf.gii ${StudyFolder}/${Subject}/T1w/${Subject}.R.midthickness.${HighResMesh}k_fs_LR.surf.gii
	# create cifti and gift MyelinMap in the low res mesh spaces
	for LowResMesh in "${LowResMeshesArray[@]}" ; do
		for MyelinMap in MyelinMap SmoothedMyelinMap ; do
			${CARET7DIR}/wb_command -cifti-resample ${AtlasSpaceFolder}/${NativeFolder}/${Subject}.${MyelinMap}_BC.native.dscalar.nii \
				COLUMN ${AtlasSpaceFolder}/fsaverage_LR${LowResMesh}k/${Subject}.${MyelinMap}.${LowResMesh}k_fs_LR.dscalar.nii \
				COLUMN ADAP_BARY_AREA ENCLOSING_VOXEL \
				${AtlasSpaceFolder}/fsaverage_LR${LowResMesh}k/${Subject}.${MyelinMap}_BC.${LowResMesh}k_fs_LR.dscalar.nii \
				-surface-postdilate 40 \
				-left-spheres ${AtlasSpaceFolder}/${NativeFolder}/${Subject}.L.sphere.MSMSulc.native.surf.gii ${AtlasSpaceFolder}/fsaverage_LR${LowResMesh}k/${Subject}.L.sphere.${LowResMesh}k_fs_LR.surf.gii \
				-left-area-surfs ${StudyFolder}/${Subject}/T1w/${NativeFolder}/${Subject}.L.midthickness.native.surf.gii ${StudyFolder}/${Subject}/T1w/fsaverage_LR${LowResMesh}k/${Subject}.L.midthickness.${LowResMesh}k_fs_LR.surf.gii \
				-right-spheres ${AtlasSpaceFolder}/${NativeFolder}/${Subject}.R.sphere.MSMSulc.native.surf.gii ${AtlasSpaceFolder}/fsaverage_LR${LowResMesh}k/${Subject}.R.sphere.${LowResMesh}k_fs_LR.surf.gii \
				-right-area-surfs ${StudyFolder}/${Subject}/T1w/${NativeFolder}/${Subject}.R.midthickness.native.surf.gii ${StudyFolder}/${Subject}/T1w/fsaverage_LR${LowResMesh}k/${Subject}.R.midthickness.${LowResMesh}k_fs_LR.surf.gii
			# gifti files
			${CARET7DIR}/wb_command -cifti-separate ${AtlasSpaceFolder}/fsaverage_LR${LowResMesh}k/${Subject}.${MyelinMap}_BC.${LowResMesh}k_fs_LR.dscalar.nii COLUMN \
				-metric CORTEX_LEFT ${AtlasSpaceFolder}/fsaverage_LR${LowResMesh}k/${Subject}.L.${MyelinMap}_BC.${LowResMesh}k_fs_LR.func.gii \
				-metric CORTEX_RIGHT ${AtlasSpaceFolder}/fsaverage_LR${LowResMesh}k/${Subject}.R.${MyelinMap}_BC.${LowResMesh}k_fs_LR.func.gii
		done
	done
fi
#Add CIFTI Maps to Spec Files

MapListDscalar="corrThickness@dscalar"
if [ "${T2wPresent}" = "YES" ] ; then
  MapListDscalar+=" MyelinMap_BC@dscalar SmoothedMyelinMap_BC@dscalar"
fi

LowResMeshListII=""
for LowResMesh in "${LowResMeshesArray[@]}" ; do
  LowResMeshListII+="${AtlasSpaceFolder}/fsaverage_LR${LowResMesh}k@${AtlasSpaceFolder}/fsaverage_LR${LowResMesh}k@${LowResMesh}k_fs_LR ${T1wFolder}/fsaverage_LR${LowResMesh}k@${AtlasSpaceFolder}/fsaverage_LR${LowResMesh}k@${LowResMesh}k_fs_LR "
done

for STRING in "$T1wFolder"/"$NativeFolder"@"$AtlasSpaceFolder"/"$NativeFolder"@native "$AtlasSpaceFolder"/"$NativeFolder"@"$AtlasSpaceFolder"/"$NativeFolder"@native "$AtlasSpaceFolder"@"$AtlasSpaceFolder"@"$HighResMesh"k_fs_LR ${LowResMeshListII} ; do
  FolderI=`echo $STRING | cut -d "@" -f 1`
  FolderII=`echo $STRING | cut -d "@" -f 2`
  Mesh=`echo $STRING | cut -d "@" -f 3`

  for STRINGII in $MapListDscalar ; do
    Map=`echo $STRINGII | cut -d "@" -f 1`
    Ext=`echo $STRINGII | cut -d "@" -f 2`
    ${CARET7DIR}/wb_command -add-to-spec-file "$FolderI"/"$Subject"."$Mesh".wb.spec INVALID "$FolderII"/"$Subject"."$Map"."$Mesh"."$Ext".nii
  done
done

rm ${StudyFolder}/${Subject}/T1w/${Subject}.L.midthickness.${HighResMesh}k_fs_LR.surf.gii ${StudyFolder}/${Subject}/T1w/${Subject}.R.midthickness.${HighResMesh}k_fs_LR.surf.gii

verbose_green_echo "---> Finished ${script_name}"
verbose_echo " "

log_Msg "END"
