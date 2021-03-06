#define MAX_NUM_LINESEGS 1000
#define MAX_INT          0x7FFFFFFF
#define MATCH_TOLERANCE  0.00001

// A vertex
typedef struct _VERTEX
{
   double x;
   double y;
} VERTEX;

// A potentially split piece of a line segment, as processed from the
// base line in the original list
typedef struct _LINESEG
{
   _LINESEG *pnextlineseg;
    int startvertex;
    int endvertex;
    double walltop;
    double wallbottom;
    double tstart;
    double tend;
    int color;
    _LINESEG *pfronttree;
    _LINESEG *pbacktree;
} LINESEG, *PLINESEG;

static VERTEX *pvertexlist;
static int NumCompiledLinesegs = 0;
static LINESEG *pCompiledLinesegs;


// Builds a BSP tree from the specified line list. List must contain
// at least one entry. If pCurrentTree is NULL, then this is the root
// node, otherwise pCurrentTree is the tree that's been build so far.
// Returns NULL for errors.

LINESEG * SelectBSPTree(LINESEG * plineseghead,
    LINESEG * pCurrentTree, LINESEG ** pParentsChildPointer)
{
    LINESEG *pminsplit;
    int minsplits;
    int tempsplitcount;
    LINESEG *prootline;
    LINESEG *pcurrentline;
    double nx, ny, numer, denom, t;

    // Pick a line as the root, and remove it from the list of lines
    // to be categorized. The line we'll select is the one of those in
    // the list that splits the fewest of the other lines in the list
    minsplits = MAX_INT;
    prootline = plineseghead;

    while (prootline != NULL) {
        pcurrentline = plineseghead;
        tempsplitcount = 0;

        while (pcurrentline != NULL) {

            // See how many other lines the current line splits
            nx = pvertexlist[prootline->startvertex].y -
                    pvertexlist[prootline->endvertex].y;
            ny = -(pvertexlist[prootline->startvertex].x -
                    pvertexlist[prootline->endvertex].x);

            // Calculate the dot products we'll need for line
            // intersection and spatial relationship
            numer = (nx * (pvertexlist[pcurrentline->startvertex].x -
                    pvertexlist[prootline->startvertex].x)) +
                    (ny * (pvertexlist[pcurrentline->startvertex].y -
                    pvertexlist[prootline->startvertex].y));
            denom = ((-nx) * (pvertexlist[pcurrentline->endvertex].x -
                    pvertexlist[pcurrentline->startvertex].x)) +
                    ((-ny) * (pvertexlist[pcurrentline->endvertex].y -
                    pvertexlist[pcurrentline->startvertex].y));

            // Figure out if the infinite lines of the current line
            // and the root intersect; if so, figure out if the
            // current line segment is actually split, split if so,
            // and add front/back polygons as appropriate
            if (denom == 0.0) {
                // No intersection, because lines are parallel; no
                // split, so nothing to do
            } else {
                // Infinite lines intersect; figure out whether the
                // actual line segment intersects the infinite line
                // of the root, and split if so
                t =  numer / denom;

                if ((t > pcurrentline->tstart) &&
                        (t < pcurrentline->tend)) {
                    // The root splits the current line
                    tempsplitcount++;
                } else {
                    // Intersection outside segment limits, so no
                    // split, nothing to do
                }
            }

            pcurrentline = pcurrentline->pnextlineseg;
        }

        if (tempsplitcount < minsplits) {
            pminsplit = prootline;
            minsplits = tempsplitcount;
        }

        prootline = prootline->pnextlineseg;
    }

    // For now, make this a leaf node so we can traverse the tree
    // as it is at this point. BuildBSPTree() will add children as
    // appropriate
    pminsplit->pfronttree = NULL;
    pminsplit->pbacktree = NULL;

    // Point the parent's child pointer to this node, so we can
    // track the currently-build tree
    *pParentsChildPointer = pminsplit;

    return BuildBSPTree(plineseghead, pminsplit, pCurrentTree);
}

// Builds a BSP tree given the specified root, by creating front and
// back lists from the remaining lines, and calling itself recursively

LINESEG * BuildBSPTree(LINESEG * plineseghead, LINESEG * prootline,
    LINESEG * pCurrentTree)
{
    LINESEG *pfrontlines;
    LINESEG *pbacklines;
    LINESEG *pcurrentline;
    LINESEG *pnextlineseg;
    LINESEG *psplitline;
    double nx, ny, numer, denom, t;
    int Done;

    // Categorize all non-root lines as either in front of the root's
    // infinite line, behind the root's infinite line, or split by the
    // root's infinite line, in which case we split it into two lines
    pfrontlines = NULL;
    pbacklines = NULL;

    pcurrentline = plineseghead;

    while (pcurrentline != NULL)
    {
      // Skip the root line when encountered
      if (pcurrentline == prootline) {
        pcurrentline = pcurrentline->pnextlineseg;
      } else  {
        nx = pvertexlist[prootline->startvertex].y -
                pvertexlist[prootline->endvertex].y;
        ny = -(pvertexlist[prootline->startvertex].x -
                pvertexlist[prootline->endvertex].x);

        // Calculate the dot products we'll need for line intersection
        // and spatial relationship
        numer = (nx * (pvertexlist[pcurrentline->startvertex].x -
                 pvertexlist[prootline->startvertex].x)) +
                (ny * (pvertexlist[pcurrentline->startvertex].y -
                 pvertexlist[prootline->startvertex].y));
        denom = ((-nx) * (pvertexlist[pcurrentline->endvertex].x -
                 pvertexlist[pcurrentline->startvertex].x)) +
                (-(ny) * (pvertexlist[pcurrentline->endvertex].y -
                 pvertexlist[pcurrentline->startvertex].y));

        // Figure out if the infinite lines of the current line and
        // the root intersect; if so, figure out if the current line
        // segment is actually split, split if so, and add front/back
        // polygons as appropriate
        if (denom == 0.0) {
            // No intersection, because lines are parallel; just add
            // to appropriate list
            pnextlineseg = pcurrentline->pnextlineseg;

            if (numer < 0.0) {
                // Current line is in front of root line; link into
                // front list
                pcurrentline->pnextlineseg = pfrontlines;
                pfrontlines = pcurrentline;
            } else {
                // Current line behind root line; link into back list
                pcurrentline->pnextlineseg = pbacklines;
                pbacklines = pcurrentline;
            }

            pcurrentline = pnextlineseg;
        } else {
            // Infinite lines intersect; figure out whether the actual
            // line segment intersects the infinite line of the root,
            // and split if so
            t =  numer / denom;

            if ((t > pcurrentline->tstart) &&
                    (t < pcurrentline->tend)) {
                // The line segment must be split; add one split
                // segment to each list
                if (NumCompiledLinesegs > (MAX_NUM_LINESEGS - 1)) {
                    DisplayMessageBox("Out of space for line segs; "
                                 "increase MAX_NUM_LINESEGS");
                    return NULL;
                }

                // Make a new line entry for the split part of line
                psplitline = &pCompiledLinesegs[NumCompiledLinesegs];
                NumCompiledLinesegs++;

                *psplitline = *pcurrentline;
                psplitline->tstart = t;
                pcurrentline->tend = t;
                
                pnextlineseg = pcurrentline->pnextlineseg;

                if (numer < 0.0) {
                    // Presplit part is in front of root line; link
                    // into front list and put postsplit part in back
                    // list
                    pcurrentline->pnextlineseg = pfrontlines;
                    pfrontlines = pcurrentline;

                    psplitline->pnextlineseg = pbacklines;
                    pbacklines = psplitline;
                } else {
                    // Presplit part is in back of root line; link
                    // into back list and put postsplit part in front
                    // list
                    psplitline->pnextlineseg = pfrontlines;
                    pfrontlines = psplitline;

                    pcurrentline->pnextlineseg = pbacklines;
                    pbacklines = pcurrentline;
                }

                pcurrentline = pnextlineseg;
            } else {
                // Intersection outside segment limits, so no need to
                // split; just add to proper list
                pnextlineseg = pcurrentline->pnextlineseg;

                Done = 0;
                while (!Done) {
                    if (numer < -MATCH_TOLERANCE) {
                        // Current line is in front of root line;
                        // link into front list
                        pcurrentline->pnextlineseg = pfrontlines;
                        pfrontlines = pcurrentline;
                        Done = 1;
                    } else if (numer > MATCH_TOLERANCE) {
                        // Current line is behind root line; link
                        // into back list
                        pcurrentline->pnextlineseg = pbacklines;
                        pbacklines = pcurrentline;
                        Done = 1;
                    } else {
                        // The point on the current line we picked to
                        // do front/back evaluation happens to be
                        // collinear with the root, so use the other
                        // end of the current line and try again
                        numer =
                            (nx *
                             (pvertexlist[pcurrentline->endvertex].x -
                              pvertexlist[prootline->startvertex].x))+
                            (ny *
                             (pvertexlist[pcurrentline->endvertex].y -
                              pvertexlist[prootline->startvertex].y));
                    }
                }

                pcurrentline = pnextlineseg;
            }
        }
      }
    }

    // Make a node out of the root line, with the front and back trees
    // attached
    if (pfrontlines == NULL) {
        prootline->pfronttree = NULL;
    } else {
        if (!SelectBSPTree(pfrontlines, pCurrentTree,
                          &prootline->pfronttree)) {
            return NULL;
        }
    }

    if (pbacklines == NULL) {
        prootline->pbacktree = NULL;
    } else {
        if (!SelectBSPTree(pbacklines, pCurrentTree,
                          &prootline->pbacktree)) {
            return NULL;
        }
    }

    return(prootline);
}
