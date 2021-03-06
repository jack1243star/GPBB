/* Draws all visible faces in the specified polygon-based object.  The
   object must have previously been transformed and projected, so that
   all vertex arrays are filled in. Ambient and diffuse shading are
   supported. */

#include "polygon.h"

void DrawPObject(PObject * ObjectToXform)
{
   int i, j, NumFaces = ObjectToXform->NumFaces, NumVertices;
   int * VertNumsPtr, Spot;
   Face * FacePtr = ObjectToXform->FaceList;
   Point * ScreenPoints = ObjectToXform->ScreenVertexList;
   PointListHeader Polygon;
   Fixedpoint Diffusion;
   ModelColor ColorTemp;
   ModelIntensity IntensityTemp;
   Point3 UnitNormal, *NormalStartpoint, *NormalEndpoint;
   long v1, v2, w1, w2;
   Point Vertices[MAX_POLY_LENGTH];

   /* Draw each visible face (polygon) of the object in turn */
   for (i=0; i<NumFaces; i++, FacePtr++) {
      /* Remember where we can find the start and end of the polygon's
         unit normal in view space, and skip over the unit normal endpoint
         entry. The end and start points of the unit normal to the polygon
         must be the first and second entries in the polgyon's vertex list.
         Note that the second point is also an active polygon vertex */
      VertNumsPtr = FacePtr->VertNums;
      NormalEndpoint = &ObjectToXform->XformedVertexList[*VertNumsPtr++];
      NormalStartpoint = &ObjectToXform->XformedVertexList[*VertNumsPtr];

      /* Copy over the face's vertices from the vertex list */
      NumVertices = FacePtr->NumVerts;
      for (j=0; j<NumVertices; j++)
         Vertices[j] = ScreenPoints[*VertNumsPtr++];

      /* Draw only if outside face showing (if the normal to the polygon
         in screen coordinates points toward the viewer; that is, has a
         positive Z component) */
      v1 = Vertices[1].X - Vertices[0].X;
      w1 = Vertices[NumVertices-1].X - Vertices[0].X;
      v2 = Vertices[1].Y - Vertices[0].Y;
      w2 = Vertices[NumVertices-1].Y - Vertices[0].Y;
      if ((v1*w2 - v2*w1) > 0) {
         /* It is facing the screen, so draw */
         /* Appropriately adjust the extent of the rectangle used to
            erase this object later */
         for (j=0; j<NumVertices; j++) {
            if (Vertices[j].X >
                  ObjectToXform->EraseRect[NonDisplayedPage].Right)
               if (Vertices[j].X < SCREEN_WIDTH)
                  ObjectToXform->EraseRect[NonDisplayedPage].Right =
                        Vertices[j].X;
               else ObjectToXform->EraseRect[NonDisplayedPage].Right =
                     SCREEN_WIDTH;
            if (Vertices[j].Y >
                  ObjectToXform->EraseRect[NonDisplayedPage].Bottom)
               if (Vertices[j].Y < SCREEN_HEIGHT)
                  ObjectToXform->EraseRect[NonDisplayedPage].Bottom =
                        Vertices[j].Y;
               else ObjectToXform->EraseRect[NonDisplayedPage].Bottom=
                     SCREEN_HEIGHT;
            if (Vertices[j].X <
                  ObjectToXform->EraseRect[NonDisplayedPage].Left)
               if (Vertices[j].X > 0)
                  ObjectToXform->EraseRect[NonDisplayedPage].Left =
                        Vertices[j].X;
               else ObjectToXform->EraseRect[NonDisplayedPage].Left=0;
            if (Vertices[j].Y <
                  ObjectToXform->EraseRect[NonDisplayedPage].Top)
               if (Vertices[j].Y > 0)
                  ObjectToXform->EraseRect[NonDisplayedPage].Top =
                        Vertices[j].Y;
               else ObjectToXform->EraseRect[NonDisplayedPage].Top=0;
         }

         /* See if there's any shading */
         if (FacePtr->ShadingType == NO_SHADING) {
            /* No shading in effect, so just draw */
            DRAW_POLYGON(Vertices, NumVertices, FacePtr->ColorIndex, 0, 0);
         } else if (FacePtr->ShadingType & TEXTURE_MAPPED_SHADING) {
            /* Texture mapping in effect; this precludes illuminated
                shading */
            DRAW_TEXTURED_POLYGON(Vertices, NumVertices, FacePtr->TexVerts,
                  FacePtr->TexMap);
         } else {
            /* Handle shading */

            /* Do ambient shading, if enabled */
            if (AmbientOn && (FacePtr->ShadingType & AMBIENT_SHADING)) {
               /* Use the ambient shading component */
               IntensityTemp = AmbientIntensity;
            } else {
               SET_INTENSITY(IntensityTemp, 0, 0, 0);
            }

            /* Do diffuse shading, if enabled */
            if (FacePtr->ShadingType & DIFFUSE_SHADING) {
               /* Calculate the unit normal for this polygon, for use in dot
                  products */
               UnitNormal.X = NormalEndpoint->X - NormalStartpoint->X;
               UnitNormal.Y = NormalEndpoint->Y - NormalStartpoint->Y;
               UnitNormal.Z = NormalEndpoint->Z - NormalStartpoint->Z;
               /* Calculate the diffuse shading component for each active
                  spotlight */
               for (Spot=0; Spot<MAX_SPOTS; Spot++) {
                  if (SpotOn[Spot] != 0) {
                     /* Spot is on, so sum, for each color component, the
                        intensity, accounting for the angle of the light rays
                        relative to the orientation of the polygon */
                     /* Calculate cosine of angle between the light and the
                        polygon normal; skip if spot is shining from behind
                        the polygon */
                     if ((Diffusion = DOT_PRODUCT(SpotDirectionView[Spot],
                           UnitNormal)) > 0) {
                        IntensityTemp.Red +=
                              FixedMul(SpotIntensity[Spot].Red, Diffusion);
                        IntensityTemp.Green +=
                              FixedMul(SpotIntensity[Spot].Green, Diffusion);
                        IntensityTemp.Blue +=
                              FixedMul(SpotIntensity[Spot].Blue, Diffusion);
                     }
                  }
               }
            }

            /* Convert the drawing color to the desired fraction of the
               brightest possible color */
            IntensityAdjustColor(&ColorTemp, &FacePtr->FullColor,
                  &IntensityTemp);

            /* Draw with the cumulative shading, converting from the general
               color representation to the best-match color index */
            DRAW_POLYGON(Vertices, NumVertices,
                  ModelColorToColorIndex(&ColorTemp), 0, 0);
         }
      }
   }
}

